//+------------------------------------------------------------------+
//|                                       smaGUY Simple Auto SLTP.mq5|
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Simple Trade Manager"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Input Parameters
input group "=== Stop Loss & Take Profit ==="
input double InpStopLoss = 50;           // Stop Loss (points)
input double InpTakeProfit = 100;        // Take Profit (points)
input bool InpCurrentSymbolOnly = true;  // Apply to current symbol only

input group "=== Trailing Stop ==="
input bool InpEnableTrailing = false;    // Enable Trailing Stop
input double InpTrailingStart = 30;      // Trailing Start (points in profit)
input double InpTrailingStep = 10;       // Trailing Step (points)

// Global Variables
CTrade trade;
datetime last_trail_check = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Simple Trade Manager Initialized ===");
   Print("SL: ", InpStopLoss, " pts | TP: ", InpTakeProfit, " pts");
   Print("Trailing: ", InpEnableTrailing ? "Enabled" : "Disabled");
   Print("Symbol Filter: ", InpCurrentSymbolOnly ? "Current Only" : "All Symbols");
   
   // Process existing positions/orders on startup
   ProcessAllTrades();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Efficient event-driven approach              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // React only to relevant trade events
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_POSITION ||
      trans.type == TRADE_TRANSACTION_ORDER_ADD)
   {
      // Small delay to ensure position is fully registered
      Sleep(100);
      
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD || trans.type == TRADE_TRANSACTION_POSITION)
      {
         // New position opened
         if(PositionSelectByTicket(trans.position))
         {
            string symbol = PositionGetString(POSITION_SYMBOL);
            if(!InpCurrentSymbolOnly || symbol == _Symbol)
               SetPositionSLTP(trans.position, symbol);
         }
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
      {
         // New pending order placed
         if(OrderSelect(trans.order))
         {
            string symbol = OrderGetString(ORDER_SYMBOL);
            if(!InpCurrentSymbolOnly || symbol == _Symbol)
               SetOrderSLTP(trans.order, symbol);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick - Only for trailing stop (lightweight check)              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!InpEnableTrailing) return;
   
   // Check trailing only every 1 second to reduce load
   datetime current_time = TimeCurrent();
   if(current_time == last_trail_check) return;
   last_trail_check = current_time;
   
   TrailAllPositions();
}

//+------------------------------------------------------------------+
//| Process all existing trades on startup                            |
//+------------------------------------------------------------------+
void ProcessAllTrades()
{
   // Process all open positions
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(!InpCurrentSymbolOnly || symbol == _Symbol)
            SetPositionSLTP(ticket, symbol);
      }
   }
   
   // Process all pending orders
   total = OrdersTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         string symbol = OrderGetString(ORDER_SYMBOL);
         if(!InpCurrentSymbolOnly || symbol == _Symbol)
            SetOrderSLTP(ticket, symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Set SL/TP for open position                                       |
//+------------------------------------------------------------------+
void SetPositionSLTP(ulong ticket, string symbol)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_tp = PositionGetDouble(POSITION_TP);
   
   // Skip if both already set
   if(current_sl != 0 && current_tp != 0) return;
   
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int sym_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   double new_sl = current_sl;
   double new_tp = current_tp;
   
   // Calculate SL if not set
   if(current_sl == 0 && InpStopLoss > 0)
   {
      if(type == POSITION_TYPE_BUY)
         new_sl = NormalizeDouble(open_price - InpStopLoss * point, sym_digits);
      else
         new_sl = NormalizeDouble(open_price + InpStopLoss * point, sym_digits);
   }
   
   // Calculate TP if not set
   if(current_tp == 0 && InpTakeProfit > 0)
   {
      if(type == POSITION_TYPE_BUY)
         new_tp = NormalizeDouble(open_price + InpTakeProfit * point, sym_digits);
      else
         new_tp = NormalizeDouble(open_price - InpTakeProfit * point, sym_digits);
   }
   
   // Modify position
   if(new_sl != current_sl || new_tp != current_tp)
   {
      if(!trade.PositionModify(ticket, new_sl, new_tp))
         Print("Error modifying position ", ticket, ": ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Set SL/TP for pending order                                       |
//+------------------------------------------------------------------+
void SetOrderSLTP(ulong ticket, string symbol)
{
   if(!OrderSelect(ticket)) return;
   
   double current_sl = OrderGetDouble(ORDER_SL);
   double current_tp = OrderGetDouble(ORDER_TP);
   
   // Skip if both already set
   if(current_sl != 0 && current_tp != 0) return;
   
   double open_price = OrderGetDouble(ORDER_PRICE_OPEN);
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int sym_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   double new_sl = current_sl;
   double new_tp = current_tp;
   
   // Calculate SL if not set
   if(current_sl == 0 && InpStopLoss > 0)
   {
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT)
         new_sl = NormalizeDouble(open_price - InpStopLoss * point, sym_digits);
      else
         new_sl = NormalizeDouble(open_price + InpStopLoss * point, sym_digits);
   }
   
   // Calculate TP if not set
   if(current_tp == 0 && InpTakeProfit > 0)
   {
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT)
         new_tp = NormalizeDouble(open_price + InpTakeProfit * point, sym_digits);
      else
         new_tp = NormalizeDouble(open_price - InpTakeProfit * point, sym_digits);
   }
   
   // Modify order
   if(new_sl != current_sl || new_tp != current_tp)
   {
      if(!trade.OrderModify(ticket, open_price, new_sl, new_tp, 
                            ORDER_TIME_GTC, 0))
         Print("Error modifying order ", ticket, ": ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Trail all positions (called max once per second)                 |
//+------------------------------------------------------------------+
void TrailAllPositions()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(!InpCurrentSymbolOnly || symbol == _Symbol)
            TrailPosition(ticket, symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Trail individual position                                          |
//+------------------------------------------------------------------+
void TrailPosition(ulong ticket, string symbol)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double current_sl = PositionGetDouble(POSITION_SL);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int sym_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double current_price = (type == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   double profit_points = 0;
   double new_sl = 0;
   
   if(type == POSITION_TYPE_BUY)
   {
      profit_points = (current_price - open_price) / point;
      
      // Check if profit reached trailing start
      if(profit_points >= InpTrailingStart)
      {
         new_sl = NormalizeDouble(current_price - InpTrailingStep * point, sym_digits);
         
         // Only move SL up, never down
         if(new_sl > current_sl)
         {
            if(!trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
               Print("Trailing error for #", ticket, ": ", trade.ResultRetcodeDescription());
         }
      }
   }
   else // SELL
   {
      profit_points = (open_price - current_price) / point;
      
      // Check if profit reached trailing start
      if(profit_points >= InpTrailingStart)
      {
         new_sl = NormalizeDouble(current_price + InpTrailingStep * point, sym_digits);
         
         // Only move SL down, never up
         if(new_sl < current_sl || current_sl == 0)
         {
            if(!trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
               Print("Trailing error for #", ticket, ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
