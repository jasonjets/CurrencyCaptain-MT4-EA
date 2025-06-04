//+------------------------------------------------------------------+
//|                                                   CurrencyCaptain.mq4 |
//|                                                Currency Captain |
//|                                        https://currencycaptain.com |
//+------------------------------------------------------------------+
#property copyright "Currency Captain"
#property link "https://currencycaptain.com"
#property version "1.01"

//+------------------------------------------------------------------+
//|    User API Key From App.
//+------------------------------------------------------------------+
input string CURRENCYCAPTAIN_API_KEY; // Currency Captain API Key
string full_user_id = "user_" + CURRENCYCAPTAIN_API_KEY;
string POST="POST" ;
string PUT="PUT" ;
string DELETE="DELETE" ;
string GET="GET";

int highest_pushed_ticket = 0;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{  
   if(MQLInfoInteger(MQL_TESTER)) return (INIT_SUCCEEDED);
   
   // Check subscription first
   int subscriptionStatus = check_currency_captain_account();
   if(subscriptionStatus != 200)
   {
      Print("Currency Captain: No active subscription found. Status: ", subscriptionStatus);
      EventKillTimer();
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
      ChartSetInteger(0, CHART_SHOW_GRID, true);
      ExpertRemove();
      return INIT_FAILED;
   }
   
   // Create/Update account
   Print("Currency Captain: Initializing account...");
   int accountResponse = create_account();
   if(accountResponse != 200) {
      Print("Currency Captain: Failed to create/update account. Response: ", accountResponse);
      return INIT_FAILED;
   }
   
   // Initial trade history sync
   Print("Currency Captain: Starting initial trade history sync...");
   if(!sync_full_trade_history()) {
      Print("Currency Captain: Failed to sync trade history");
      return INIT_FAILED;
   }
   
   // Setup chart and timer
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'11,18,75');
   ChartSetInteger(0, CHART_SHOW_GRID, 0);   
   EventSetTimer(10); // Update every 10 seconds
   
   Print("Currency Captain: Initialization complete - Monitoring trades");
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Sync full trade history                                         |
//+------------------------------------------------------------------+
bool sync_full_trade_history()
{
   datetime end_time = TimeCurrent();
   datetime start_time = end_time - (60 * 24 * 60 * 60); // 60 days
   
   // First, delete existing trade history
   string delete_url = "https://currencycaptain.com/api/MT4/tradehistory/" + full_user_id + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   char empty[];
   char response_buffer[];
   string headers = "Content-Type: application/json";
   string result_headers;
   
   Print("Currency Captain: Clearing existing trade history...");
   int delete_response = WebRequest(DELETE, delete_url, headers, 5000, empty, response_buffer, result_headers);
   if(delete_response != 200) {
      Print("Currency Captain: Failed to clear trade history. Response: ", delete_response);
      return false;
   }
   
   // Now upload all trades
   string url = "https://currencycaptain.com/api/MT4/trade";
   string account_number_str = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string trades_data = "[";
   bool has_trades = false;
   int total_processed = 0;
   
   // Process closed trades
   Print("Currency Captain: Processing historical trades...");
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderCloseTime() < start_time) continue;
      
      if(has_trades) trades_data += ",";
      trades_data += create_historical_trade_json(account_number_str);
      has_trades = true;
      total_processed++;
      
      // Send batch if it's getting large
      if(StringLen(trades_data) > 1000000) {
         trades_data += "]";
         if(!send_trades_batch(trades_data, url, headers)) return false;
         trades_data = "[";
         has_trades = false;
      }
   }
   
   // Process open trades
   Print("Currency Captain: Processing open trades...");
   for(int j = 0; j < OrdersTotal(); j++) {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      
      if(has_trades) trades_data += ",";
      trades_data += create_historical_trade_json(account_number_str);
      has_trades = true;
      total_processed++;
   }
   
   // Send final batch if there are trades
   if(has_trades) {
      trades_data += "]";
      if(!send_trades_batch(trades_data, url, headers)) return false;
   }
   
   Print("Currency Captain: Successfully synced ", total_processed, " trades");
   return true;
}

//+------------------------------------------------------------------+
//| Send batch of trades                                            |
//+------------------------------------------------------------------+
bool send_trades_batch(string trades_data, string url, string headers)
{
   char data_array[];
   char response_buffer[];
   string result_headers;
   
   StringToCharArray(trades_data, data_array, 0, StringLen(trades_data), CP_UTF8);
   int response = WebRequest(POST, url, headers, 5000, data_array, response_buffer, result_headers);
   
   if(response != 200) {
      Print("Currency Captain: Failed to upload trade batch. Response: ", response);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Update account data
   create_account();
}

//+------------------------------------------------------------------+
//| Trade event function                                            |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Get the last order
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         process_single_trade();
         break;
      }
   }
   
   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--) {
      if(OrderSelect(j, SELECT_BY_POS, MODE_HISTORY)) {
         process_single_trade();
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Process single trade                                            |
//+------------------------------------------------------------------+
void process_single_trade()
{
   string account_number_str = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string trade_data = "[" + create_historical_trade_json(account_number_str) + "]";
   
   string headers = "Content-Type: application/json";
   string url = "https://currencycaptain.com/api/MT4/trade";
   
   char data_array[];
   char response_buffer[];
   string result_headers;
   
   StringToCharArray(trade_data, data_array, 0, StringLen(trade_data), CP_UTF8);
   int response = WebRequest(POST, url, headers, 5000, data_array, response_buffer, result_headers);
   
   if(response != 200) {
      Print("Currency Captain: Failed to upload trade update. Response: ", response);
   } else {
      Print("Currency Captain: Successfully updated trade ", OrderTicket());
   }
}

void OnTick()
{  
   static datetime lastUpdate = 0;
   datetime currentTime = TimeCurrent();
   
   // Update account data if balance or equity changes
   static double lastBalance = 0;
   static double lastEquity = 0;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Check if values have changed or if 30 seconds have passed
   if(currentBalance != lastBalance || currentEquity != lastEquity || currentTime - lastUpdate >= 30) {
      push_account_data_to_currency_captain();
      lastBalance = currentBalance;
      lastEquity = currentEquity;
      lastUpdate = currentTime;
   }
   
   double current_drawdown = NormalizeDouble(currentBalance - currentEquity, 4);
   double current_drawdown_percentage = NormalizeDouble((current_drawdown / currentBalance) * 100, 4);

   Comment(
      "Account Balance: ", DoubleToString(currentBalance, 2), "\n",
      "Account Equity: ", DoubleToString(currentEquity, 2), "\n",
      "Current Drawdown: ", DoubleToString(current_drawdown_percentage, 2), "%\n",
      "Orders Total: ", OrdersTotal(), "\n",
      "Last Update: ", TimeToString(lastUpdate)
   );
}

//+------------------------------------------------------------------+
//|    Helper Functions
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|   PUSH / UPDATE ACCOUNTS                                         | 
//+------------------------------------------------------------------+
int push_account_data_to_currency_captain() 
{
   // Get account data
   string account_company = AccountInfoString(ACCOUNT_COMPANY);
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   long account_number = AccountInfoInteger(ACCOUNT_LOGIN);
   
   // Calculate drawdown
   double current_drawdown = account_balance - account_equity;
   double current_drawdown_percentage = NormalizeDouble((current_drawdown / account_balance) * 100, 2);
   
   // Create search string
   string search_string = StringConcatenate(full_user_id, IntegerToString(account_number));

   // Create JSON payload
   string account_data = "{" +
      "\"user_id\": \"" + full_user_id + "\"," +
      "\"balance\": " + DoubleToString(account_balance, 2) + "," +
      "\"equity\": " + DoubleToString(account_equity, 2) + "," +
      "\"current_drawdown\": " + DoubleToString(current_drawdown_percentage, 2) + "," +
      "\"company\": \"" + account_company + "\"," +
      "\"account_number\": " + IntegerToString(account_number) + "," +
      "\"password\": \"\"," +
      "\"investor_password\": \"\"" +
   "}";

   // Prepare request
   char data_array[];
   StringToCharArray(account_data, data_array, 0, StringLen(account_data), CP_UTF8);
   string headers = "Content-Type: application/json\r\nAccept: application/json";
   char response_buffer[];
   
   // First try to update (PUT with ID in URL)
   string update_endpoint = "https://currencycaptain.com/api/MT4/account/" + search_string;
   int response = WebRequest(PUT, update_endpoint, headers, 5000, data_array, response_buffer, headers);
   
   // If account doesn't exist (404), create new one (POST to base endpoint)
   if(response == 404) {
      string create_endpoint = "https://currencycaptain.com/api/MT4/account";
      response = WebRequest(POST, create_endpoint, headers, 5000, data_array, response_buffer, headers);
   }
   
   // Only show comment if there's an error
   if(response != 200) {
      Comment(
         "Operation: ", (response == 404 ? "Creating new account" : "Updating account"), "\n",
         "Endpoint: ", (response == 404 ? create_endpoint : update_endpoint), "\n",
         "Response: ", response, "\n",
         "Error: ", GetLastError()
      );
   }
   
   return response;
}

//+------------------------------------------------------------------+
//|   PUSH / UPDATE TRADES                                         |
//+------------------------------------------------------------------+
int push_trade_data_to_currency_captain()  
{
   //+------------------------------------------------------------------+
   //|        Trade History Data                                        |
   //+------------------------------------------------------------------+
   datetime currentServerTime = TimeCurrent();

   // Account Number
   long account_number = AccountInfoInteger(ACCOUNT_LOGIN);
   string account_number_str = IntegerToString(account_number);
   
   //+------------------------------------------------------------------+
   //|        API                                                       |
   //+------------------------------------------------------------------+
   int timeout = 50000;
   string headers = "Content-Type: application/json";
   string result_headers = "Content-Type: application/json";
   char response_buffer[];
   string push_data;
   char push_data_array[];
   int add_response;
   int i; // Declare loop variable once at the start

   // URLS
   string url = "https://currencycaptain.com/api/MT4/trade";
   string purge_url = "https://currencycaptain.com/api/MT4/tradehistory/" + full_user_id + "_" + account_number_str;

   // Get current open trades first
   int total_open = OrdersTotal();
   for(i = 0; i < total_open; i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      
      int current_ticket = OrderTicket();
      if(current_ticket <= highest_pushed_ticket) continue;
      
      push_data = create_trade_json(current_ticket, account_number_str);
      ArrayFree(push_data_array);
      StringToCharArray(push_data, push_data_array, 0, StringLen(push_data), CP_UTF8);
      
      add_response = WebRequest(POST, url, headers, timeout, push_data_array, response_buffer, result_headers);
      if(add_response == 200) {
         highest_pushed_ticket = current_ticket;
      }
   }

   // Then get history
   int total_history = OrdersHistoryTotal();
   for(i = 0; i < total_history; i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      
      current_ticket = OrderTicket();
      if(current_ticket <= highest_pushed_ticket) continue;
      
      push_data = create_trade_json(current_ticket, account_number_str);
      ArrayFree(push_data_array);
      StringToCharArray(push_data, push_data_array, 0, StringLen(push_data), CP_UTF8);

      add_response = WebRequest(POST, url, headers, timeout, push_data_array, response_buffer, result_headers);
      if(add_response == 200) {
         highest_pushed_ticket = current_ticket;
      }
   }
   
   return 200;
}

//+------------------------------------------------------------------+
//|   Helper function to create trade JSON                           |
//+------------------------------------------------------------------+
string create_trade_json(int ticket, string account_number_str)
{
   string thisTradeSymbol = OrderSymbol();
   string thisTradeTimeStr = TimeToString(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   string thisTradeTicketStr = IntegerToString(ticket, 2);
   string thisTradePriceStr = DoubleToString(OrderOpenPrice(), 2);
   string thisTradeVolumeStr = DoubleToString(OrderLots(), 2);
   string thisTradeCommissionStr = DoubleToString(OrderCommission(), 2);
   string thisTradeSwapStr = DoubleToString(OrderSwap(), 2);
   string thisTradeProfitStr = DoubleToString(OrderProfit(), 2);
   string thisTradeTypeStr = OrderType() == 0 ? "Buy" : "Sell";

   return "{\n"
      "   \"user_id\": \"" + full_user_id + "\",\n"
      "   \"symbol\": \"" + thisTradeSymbol + "\",\n"
      "   \"type\": \"" + thisTradeTypeStr + "\",\n"
      "   \"account\": \"" + account_number_str + "\",\n"
      "   \"ticket\": \"" + thisTradeTicketStr + "\",\n"
      "   \"date\": \"" + thisTradeTimeStr + "\",\n"
      "   \"volume\": \"" + thisTradeVolumeStr + "\",\n"
      "   \"entryPrice\": \"" + thisTradePriceStr + "\",\n"
      "   \"commission\": \"" + thisTradeCommissionStr + "\",\n"
      "   \"swap\": \"" + thisTradeSwapStr + "\",\n"
      "   \"profit\": \"" + thisTradeProfitStr + "\"\n"
   "}";
}

//+------------------------------------------------------------------+
//|   PUSH TRADES ON CLOSE                                           |
//+------------------------------------------------------------------+
int on_trade_push_trade_data_to_currency_captain() {

   // Account Number
   long account_number = AccountInfoInteger(ACCOUNT_LOGIN);
   string account_number_str = IntegerToString(account_number);

   //+------------------------------------------------------------------+
   //|        API                                                       |
   //+------------------------------------------------------------------+
   // Timeout
   int timeout = 50000;

   // Headers
   string headers = "Content-Type: application/json";
   string result_headers = "Content-Type: application/json";
   
   // Results Array
   char a[], b[];

   // URLS
   string url = "https://currencycaptain.com/api/MT4/trade";

   //+------------------------------------------------------------------+
   //|        Trade History Data                                        |
   //+------------------------------------------------------------------+
   // Calculate start and end dates for the last two weeks
   datetime currentServerTime = TimeCurrent();
   datetime twoWeeksAgo = currentServerTime - 1 * 500 * 60 * 60; // 14 days in seconds

   // Request trade history for the last two weeks
   //bool last_two_weeks = HistorySelect(twoWeeksAgo, currentServerTime);
   
   int total_deals = OrdersTotal() ;
   ulong ticket = OrderTicket() ;

   if (0 == 0) 
   {
      
      // Variables to store trade data
      ulong thisTradeTicket = ticket;
      double thisTradePrice = 0;
      datetime thisTradeTime = 0;
      string thisTradeSymbol;
      long thisTradeType = 0;
      long thisTradeEntry = 0;
      double thisTradeProfit = 0;
      double thisTradeCommission = 0;
      double thisTradeVolume = 0;
      double thisTradeSwap = 0;
      string thisTradeComment = "";

      

      // Get Actual Account Trade Data
      thisTradeSymbol = OrderSymbol();        // Symbol
      thisTradeTime = (datetime)OrderCloseTime(); // Date                                      // Ticket
      thisTradeType = OrderType();           // Type
      thisTradeVolume = OrderLots();       // Volume
      thisTradePrice = OrderOpenPrice();          // Entry Price
      thisTradeCommission = OrderCommission(); // Commission
      thisTradeSwap = OrderSwap();             // Swap
      thisTradeProfit = OrderProfit();         // Profit
      //thisTradeComment = HistoryDealGetString(ticket, DEAL_COMMENT); //  Comment


      // Convert double variables to strings
      string thisTradeTimeStr = IntegerToString(thisTradeTime);
      string thisTradeTicketStr = IntegerToString(ticket , 2) ;
      string thisTradePriceStr = DoubleToString(thisTradePrice, 2);
      string thisTradeVolumeStr = DoubleToString(thisTradeVolume, 2);
      string thisTradeCommissionStr = DoubleToString(thisTradeCommission, 2);
      string thisTradeSwapStr = DoubleToString(thisTradeSwap, 2);
      string thisTradeProfitStr = DoubleToString(thisTradeProfit, 2);

      //+------------------------------------------------------------------+
      //|        Send Requests                                             |
      //+------------------------------------------------------------------+
      // New Account Info
      string push_data = "{\n"
         "   \"user_id\": \"" + full_user_id + "\",\n"
         "   \"symbol\": \"" + thisTradeSymbol + "\",\n"
         "   \"account\": \"" +account_number_str + "\",\n"
         "   \"ticket\": \"" + thisTradeTicketStr + "\",\n"
         "   \"date\": \"" + thisTradeTime + "\",\n"
         "   \"volume\": \"" +thisTradeVolumeStr + "\",\n"
         "   \"entryPrice\": \"" +thisTradePriceStr + "\",\n"
         "   \"commission\": \"" +thisTradeCommissionStr + "\",\n"
         "   \"swap\": \"" + thisTradeSwapStr + "\",\n"
         "   \"profit\": \"" + thisTradeProfitStr + "\"\n"
      "}";

      char push_data_array[]; // Declare a character array to store the JSON data as characters
      StringToCharArray(push_data, push_data_array, 0, StringLen(push_data), CP_UTF8);

      int add_response = WebRequest(POST, url, headers, timeout, push_data_array, a, result_headers);
      return add_response ;
   } 
   
   return 200 ;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|   PURGE ACCOUNT                                                  |
//+------------------------------------------------------------------+
int purge_currency_captain_account()  
{
   // Account Number
   long account_number = AccountInfoInteger(ACCOUNT_LOGIN);
   string account_number_str = IntegerToString(account_number);
   string account_identifier = StringConcatenate(full_user_id, account_number_str); // Combine without separator

   
   //+------------------------------------------------------------------+
   //|        API                                                       |
   //+------------------------------------------------------------------+
   // Timeout
   int timeout = 50000;

   // Headers
   string headers = "Content-Type: application/json";
   string result_headers = "Content-Type: application/json";
   string result_headers2 = "Content-Type: application/json";
   
   // Results Array
   char a[], b[];

   // URLS
   string purge_trade_url = "https://currencycaptain.com/api/MT4/tradehistory/" + full_user_id + "_" + account_number_str;
   string purge_account_url = "https://currencycaptain.com/api/MT4/account/" + account_identifier;

   //+------------------------------------------------------------------+
   //|        Loop Trade History                                        |
   //+------------------------------------------------------------------+
   // Purge Trades 
   int purge_trades = WebRequest(DELETE, purge_trade_url, headers, timeout, a, b, result_headers);
   
   int purge_accounts = WebRequest(DELETE, purge_account_url, headers, timeout, a, b, result_headers2);

   if (purge_trades != 200) {return 400;} 
      else { 
      return purge_trades;
      }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|   CHECK ACCOUNT                                                  |
//+------------------------------------------------------------------+
int check_currency_captain_account()  
{
   // Timeout
   int timeout = 50000;

   // Headers
   string headers = "Content-Type: application/json";
   string result_headers = "Content-Type: application/json";
   
   // Results Array
   char a[], b[];

   // Check subscription URL
   string check_subscription = "https://currencycaptain.com/api/subscription/" + full_user_id;
   
   // Log API call
   Alert("API Call (GET) - Check Subscription\nEndpoint: ", check_subscription);

   // Check subscription status
   int check_user_status = WebRequest(GET, check_subscription, headers, timeout, a, b, result_headers);
   
   // Log response
   Alert("API Response (GET) - Check Subscription\nStatus: ", check_user_status);
   
   // If not 200, show error and return status
   if(check_user_status != 200) {
      string error_msg = "No active subscription found.\n";
      error_msg += "Please visit https://currencycaptain.com to subscribe.\n";
      error_msg += "Make sure to add https://currencycaptain.com to\n";
      error_msg += "'Allow WebRequest for listed URL' via Tools -> Options";
      
      Comment(error_msg);
      Print("Currency Captain: Subscription check failed with status ", check_user_status);
   }
   
   return check_user_status;
}

//+------------------------------------------------------------------+
//| Create initial account                                           |
//+------------------------------------------------------------------+
int create_account()
{
   string account_company = AccountInfoString(ACCOUNT_COMPANY);
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   long account_number = AccountInfoInteger(ACCOUNT_LOGIN);
   
   // Calculate drawdown
   double current_drawdown = account_balance - account_equity;
   double current_drawdown_percentage = NormalizeDouble((current_drawdown / account_balance) * 100, 2);
   
   // Create search string
   string search_string = StringConcatenate(full_user_id, IntegerToString(account_number));

   // Create JSON payload
   string account_data = "{" +
      "\"user_id\": \"" + full_user_id + "\"," +
      "\"balance\": " + DoubleToString(account_balance, 2) + "," +
      "\"equity\": " + DoubleToString(account_equity, 2) + "," +
      "\"current_drawdown\": " + DoubleToString(current_drawdown_percentage, 2) + "," +
      "\"company\": \"" + account_company + "\"," +
      "\"account_number\": " + IntegerToString(account_number) + "," +
      "\"search_string\": \"" + search_string + "\"," +
      "\"password\": \"\"," +
      "\"investor_password\": \"\"" +
   "}";

   // Log API call
   Alert("API Call (POST) - Create Account\nEndpoint: https://currencycaptain.com/api/MT4/account\nPayload: ", account_data);

   // Prepare request
   char data_array[];
   StringToCharArray(account_data, data_array, 0, StringLen(account_data), CP_UTF8);
   string headers = "Content-Type: application/json\r\nAccept: application/json";
   char response_buffer[];
   
   // Create new account using POST
   string create_endpoint = "https://currencycaptain.com/api/MT4/account";
   int response = WebRequest(POST, create_endpoint, headers, 5000, data_array, response_buffer, headers);
   
   // Log response
   Alert("API Response (POST) - Create Account\nStatus: ", response);
   
   return response;
}

//+------------------------------------------------------------------+
//| Load Historical Trades                                           |
//+------------------------------------------------------------------+
int load_historical_trades()
{
   datetime end_time = TimeCurrent();
   datetime start_time = end_time - (60 * 24 * 60 * 60); // 60 days
   
   long account_number = AccountInfoInteger(ACCOUNT_LOGIN);
   string account_number_str = IntegerToString(account_number);
   
   // Prepare common request parameters
   string headers = "Content-Type: application/json";
   string result_headers;
   char response_buffer[];
   string url = "https://currencycaptain.com/api/MT4/trade";
   int timeout = 50000;
   
   // Process trades in batches
   string batch_data = "[";
   int batch_size = 0;
   int max_batch_size = 50; // Maximum trades per request
   int response = 200;
   int total_processed = 0;
   char data_array[]; // Declare once for reuse
   
   // First process closed trades
   Print("Processing closed trades...");
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && response == 200; i--) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      
      // Skip trades older than 60 days
      if(OrderCloseTime() < start_time) continue;
      
      // Add to batch
      if(batch_size > 0) batch_data += ",";
      batch_data += create_historical_trade_json(account_number_str);
      batch_size++;
      total_processed++;
      
      // Send batch if full or last trade
      if(batch_size >= max_batch_size || i == 0) {
         if(batch_size > 0) { // Only send if we have trades
            batch_data += "]";
            
            // Log API call
            Alert("API Call (POST) - Upload Closed Trades Batch\nEndpoint: ", url, "\nPayload: ", batch_data);
            
            // Send batch
            ArrayFree(data_array); // Clear array before reuse
            StringToCharArray(batch_data, data_array, 0, StringLen(batch_data), CP_UTF8);
            response = WebRequest(POST, url, headers, timeout, data_array, response_buffer, result_headers);
            
            // Log response
            Alert("API Response (POST) - Upload Closed Trades Batch\nStatus: ", response);
            
            if(response != 200) {
               Print("Failed to upload trade batch. Response: ", response);
               return response;
            }
            
            Print("Processed batch of ", batch_size, " trades. Total processed: ", total_processed);
            
            // Reset batch
            batch_data = "[";
            batch_size = 0;
         }
      }
   }
   
   // Then process open trades
   Print("Processing open trades...");
   for(int j = OrdersTotal() - 1; j >= 0 && response == 200; j--) {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      
      // Add to batch
      if(batch_size > 0) batch_data += ",";
      batch_data += create_historical_trade_json(account_number_str);
      batch_size++;
      total_processed++;
      
      // Send batch if full or last trade
      if(batch_size >= max_batch_size || j == 0) {
         if(batch_size > 0) { // Only send if we have trades
            batch_data += "]";
            
            // Log API call
            Alert("API Call (POST) - Upload Open Trades Batch\nEndpoint: ", url, "\nPayload: ", batch_data);
            
            // Send batch
            ArrayFree(data_array); // Clear array before reuse
            StringToCharArray(batch_data, data_array, 0, StringLen(batch_data), CP_UTF8);
            response = WebRequest(POST, url, headers, timeout, data_array, response_buffer, result_headers);
            
            // Log response
            Alert("API Response (POST) - Upload Open Trades Batch\nStatus: ", response);
            
            if(response != 200) {
               Print("Failed to upload trade batch. Response: ", response);
               return response;
            }
            
            Print("Processed batch of ", batch_size, " trades. Total processed: ", total_processed);
            
            // Reset batch
            batch_data = "[";
            batch_size = 0;
         }
      }
   }
   
   Print("Total trades processed: ", total_processed);
   return 200;
}

//+------------------------------------------------------------------+
//| Create JSON for historical trade                                 |
//+------------------------------------------------------------------+
string create_historical_trade_json(string account_number_str)
{
   return "{" +
      "\"user_id\": \"" + full_user_id + "\"," +
      "\"symbol\": \"" + OrderSymbol() + "\"," +
      "\"type\": \"" + (OrderType() == OP_BUY ? "Buy" : "Sell") + "\"," +
      "\"account\": \"" + account_number_str + "\"," +
      "\"ticket\": \"" + IntegerToString(OrderTicket()) + "\"," +
      "\"date\": \"" + TimeToString(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\"," +
      "\"volume\": \"" + DoubleToString(OrderLots(), 2) + "\"," +
      "\"entryPrice\": \"" + DoubleToString(OrderOpenPrice(), 2) + "\"," +
      "\"commission\": \"" + DoubleToString(OrderCommission(), 2) + "\"," +
      "\"swap\": \"" + DoubleToString(OrderSwap(), 2) + "\"," +
      "\"profit\": \"" + DoubleToString(OrderProfit(), 2) + "\"" +
   "}";
}

//+------------------------------------------------------------------+
//| Check and upload new trades                                     |
//+------------------------------------------------------------------+
void check_and_upload_new_trades()
{
   static int last_history_total = 0;
   static int last_trades_total = 0;
   
   int current_history_total = OrdersHistoryTotal();
   int current_trades_total = OrdersTotal();
   
   // If no changes in totals, no need to check
   if(current_history_total == last_history_total && 
      current_trades_total == last_trades_total) return;
   
   // Prepare common request parameters
   string headers = "Content-Type: application/json";
   string result_headers;
   char response_buffer[];
   string url = "https://currencycaptain.com/api/MT4/trade";
   int timeout = 50000;
   string account_number_str = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   
   // Check new history trades
   if(current_history_total > last_history_total) {
      string history_trades_data = "[";
      bool has_history_trades = false;
      
      for(int hist_idx = current_history_total - 1; hist_idx >= last_history_total; hist_idx--) {
         if(!OrderSelect(hist_idx, SELECT_BY_POS, MODE_HISTORY)) continue;
         
         if(has_history_trades) history_trades_data += ",";
         history_trades_data += create_historical_trade_json(account_number_str);
         has_history_trades = true;
      }
      
      if(has_history_trades) {
         history_trades_data += "]";
         Alert("API Call (POST) - Upload New History Trades\nEndpoint: ", url, "\nPayload: ", history_trades_data);
         
         char history_data_array[];
         StringToCharArray(history_trades_data, history_data_array, 0, StringLen(history_trades_data), CP_UTF8);
         int history_response = WebRequest(POST, url, headers, timeout, history_data_array, response_buffer, result_headers);
         
         Alert("API Response (POST) - Upload New History Trades\nStatus: ", history_response);
      }
   }
   
   // Check new open trades
   if(current_trades_total != last_trades_total) {
      string open_trades_data = "[";
      bool has_open_trades = false;
      
      for(int open_idx = 0; open_idx < OrdersTotal(); open_idx++) {
         if(!OrderSelect(open_idx, SELECT_BY_POS, MODE_TRADES)) continue;
         
         if(has_open_trades) open_trades_data += ",";
         open_trades_data += create_historical_trade_json(account_number_str);
         has_open_trades = true;
      }
      
      if(has_open_trades) {
         open_trades_data += "]";
         Alert("API Call (POST) - Upload Open Trades Update\nEndpoint: ", url, "\nPayload: ", open_trades_data);
         
         char open_data_array[];
         StringToCharArray(open_trades_data, open_data_array, 0, StringLen(open_trades_data), CP_UTF8);
         int open_response = WebRequest(POST, url, headers, timeout, open_data_array, response_buffer, result_headers);
         
         Alert("API Response (POST) - Upload Open Trades Update\nStatus: ", open_response);
      }
   }
   
   // Update totals
   last_history_total = current_history_total;
   last_trades_total = current_trades_total;
}
