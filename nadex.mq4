
int OnInit()
{
   ObjectsDeleteAll() ;
   return 1;
}
void OnTick()
{
   DrawHorizontalLines(Bid, 20);  
   Comment(GetCountdownNumber()) ;
   // If countdown < 30  ( 1 minute chart )
        // If ( (bar close is > open) && (line is within 5 pips below) --> BUY
        // If ( (bar close is < open) && (line is within 5 pips above) --> SELL
    // At beginning of 5 minute, close all

        

}



void DrawHorizontalLines(double startPrice, double pipDistance) {
    double priceStep = pipDistance * Point; // Convert pips to price level
    int middleIndex = 2; // Index of the middle line

    for (int i = 0; i < 5; i++) {
        double price;
        if (i == middleIndex)
            price = startPrice;
        else if (i < middleIndex)
            price = startPrice - (middleIndex - i) * priceStep;
        else
            price = startPrice + (i - middleIndex) * priceStep;

        ObjectCreate("HorizontalLine" + IntegerToString(i), OBJ_HLINE, 0, 0, price);
        ObjectSetInteger(0, "HorizontalLine" + IntegerToString(i), OBJPROP_COLOR, clrBlue);
    }
}


string GetCountdownNumber() {
    // Get current time
    datetime current_time = TimeCurrent();
    
    // Calculate the current minute and second
    int current_minute = TimeMinute(current_time);
    int current_second = TimeSeconds(current_time);
    
    // Calculate the seconds remaining until the next 5-minute interval
    int seconds_until_next_interval = (5 - current_minute % 5) * 60 - current_second;
    
    // Adjust the seconds if we're already at the start of a new 5-minute interval
    if (seconds_until_next_interval == 300)
        seconds_until_next_interval = 0;
    
    // Convert seconds to minutes and seconds (formatted string)
    int minutes = seconds_until_next_interval / 60;
    int seconds = seconds_until_next_interval % 60;
    
    // Return countdown number as "MM:SS" string
    return StringFormat("%02d:%02d", minutes, seconds);
}