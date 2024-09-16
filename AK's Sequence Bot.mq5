//+------------------------------------------------------------------+
//|                                                    CustomEA.mq5  |
//|                        Generated using MetaEditor 5              |
//|                        http://www.metaquotes.net                 |
//+------------------------------------------------------------------+
#property strict

input int EMAPeriod = 15;
input double SL = 30;    // Initial Stop Loss in pips
input double TP = 60;    // Take Profit in pips
input double maxSpread = 2;  // Maximum spread in pipettes (0.2 pips)
input double BEPips = 30;    // Pips to move SL to break-even

// EMA handle
int emaHandle;

// Lot size progression
double lotSizes[] = {0.01, 0.01, 0.02, 0.03, 0.04, 0.06, 0.09, 0.14, 0.21, 0.31};
int lotSizeIndex = 0;
double lastBalance = 0;  // To store the last balance to check profit/loss
int consecutiveLosses = 0;  // To count consecutive stop losses
const int maxConsecutiveLosses = 10;  // Maximum allowed consecutive stop losses

datetime lastRetryTime = 0;  // Last time a trade was attempted

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Create EMA indicator
   emaHandle = iMA(_Symbol, PERIOD_M5, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   // Check if the handle is valid
   if(emaHandle == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle");
      return INIT_FAILED;
     }

   // Initialize last balance
   lastBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Release the EMA handle
   IndicatorRelease(emaHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Stop the bot if maximum consecutive losses reached
   if(consecutiveLosses >= maxConsecutiveLosses)
     {
      Print("Maximum consecutive losses reached. Stopping the bot.");
      return;
     }

   // Check if there are any open positions
   if(PositionSelect(_Symbol))
     {
      // Manage open positions
      ManageOpenPosition();
      return;
     }

   // Check if it's time to retry
   if(TimeCurrent() - lastRetryTime < 60)
      return;

   double emaCurrent[1], emaPrevious[1];

   // Get EMA values
   if(CopyBuffer(emaHandle, 0, 0, 1, emaCurrent) <= 0 || CopyBuffer(emaHandle, 0, 1, 1, emaPrevious) <= 0)
      return;

   // Determine the current spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   // Check if the spread is greater than the maximum allowed spread
   if(spread > maxSpread)
     {
      Print("Spread is too high: ", spread, " pipettes. Not taking trade.");
      lastRetryTime = TimeCurrent();  // Update the last retry time
      return;
     }

   // Determine the lot size
   double lotSize = lotSizes[lotSizeIndex];

   // Define trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   if(emaCurrent[0] > emaPrevious[0])
     {
      // Buy signal
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slPrice = price - SL * _Point;
      double tpPrice = price + TP * _Point;
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = lotSize;
      request.type = ORDER_TYPE_BUY;
      request.price = price;
      request.sl = slPrice;
      request.tp = tpPrice;
      request.deviation = 3;

      Print("Placing Buy Order: Price = ", price, ", SL = ", slPrice, ", TP = ", tpPrice);
     }
   else if(emaCurrent[0] < emaPrevious[0])
     {
      // Sell signal
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slPrice = price + SL * _Point;
      double tpPrice = price - TP * _Point;
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = lotSize;
      request.type = ORDER_TYPE_SELL;
      request.price = price;
      request.sl = slPrice;
      request.tp = tpPrice;
      request.deviation = 3;

      Print("Placing Sell Order: Price = ", price, ", SL = ", slPrice, ", TP = ", tpPrice);
     }

   // Send trade request
   if(!OrderSend(request, result))
     {
      Print("OrderSend failed: ", result.retcode);
     }
   else
     {
      // Update the last retry time only if the trade is successful
      lastRetryTime = TimeCurrent();
     }
  }
//+------------------------------------------------------------------+
//| Trade handling function                                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
  {
   // Check if the transaction is a position close
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
     {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Check if there are no open positions
      if(!PositionSelect(_Symbol))
        {
         // Retrieve the last closed position details
         ulong ticket = HistoryDealGetTicket(HistoryDealsTotal() - 1);
         double lastDealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

         if(lastDealProfit >= 0)
           {
            // Ignore trades that hit SL at break-even or in profit
            // Do nothing with lot size progression
           }
         else
           {
            // Increase lot size on loss
            lotSizeIndex = MathMin(lotSizeIndex + 1, ArraySize(lotSizes) - 1);
            consecutiveLosses++;
           }

         // Reset lot size after a take profit
         if(lastDealProfit >= TP * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE))
           {
            lotSizeIndex = 0;
            consecutiveLosses = 0;
           }

         // Update last balance value
         lastBalance = currentBalance;
        }
     }
  }
//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   double price = 0.0;
   double newSL = 0.0;
   bool updateSL = false;

   // Get the current open position
   if(PositionSelect(_Symbol))
     {
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / _Point : (openPrice - currentPrice) / _Point;

      if(profitPips >= BEPips)
        {
         // Move SL to break-even
         newSL = openPrice;
         updateSL = true;
        }

      if(updateSL)
        {
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_SLTP;
         request.symbol = _Symbol;
         request.position = PositionGetInteger(POSITION_TICKET);
         request.sl = newSL;
         request.tp = PositionGetDouble(POSITION_TP);

         if(!OrderSend(request, result))
           {
            Print("Failed to update SL: ", result.retcode);
           }
         else
           {
            Print("SL updated to: ", newSL);
           }
        }
     }
  }
//+------------------------------------------------------------------+
