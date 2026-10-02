//+------------------------------------------------------------------+
//|                                                 AZIZ_BOT_V1.mq5  |
//|                                  Copyright 2026, AZIZ BOT Project|
//+------------------------------------------------------------------+
#property copyright "AZIZ BOT V1"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Parametres d'entree
input group "=== Gestion du Risque ==="
input double   InpRiskPercent      = 1.0;   // Risque par trade (% de l'equite)
input double   InpMaxDailyLossPct  = 5.0;   // Perte max quotidienne (% de l'equite)
input int      InpMaxConsecLosses  = 3;     // Pertes consecutives max avant blocage
input int      InpMaxOpenPositions = 1;     // Nombre max de positions simultanees

input group "=== Parametres Techniques ==="
input int      InpEmaFastPeriod    = 20;    // Periode EMA Rapide
input int      InpEmaSlowPeriod    = 50;    // Periode EMA Lente
input int      InpRsiPeriod        = 14;    // Periode RSI
input double   InpRsiOversold      = 40.0;  // RSI Survendu (Achat)
input double   InpRsiOverbought    = 60.0;  // RSI Surachete (Vente)
input int      InpStopLossPips     = 150;   // Stop Loss en points (15 pips)
input int      InpTakeProfitPips   = 300;   // Take Profit en points (30 pips)

//--- Variables Globales
int      handleEmaFast;
int      handleEmaSlow;
int      handleRsi;
datetime lastBarTime;
int      consecutiveLosses = 0;
double   startingDailyEquity;
int      lastTradeDay = -1;

int OnInit()
{
   handleEmaFast = iMA(_Symbol, PERIOD_M15, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaSlow = iMA(_Symbol, PERIOD_M15, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleRsi     = iRSI(_Symbol, PERIOD_M15, InpRsiPeriod, PRICE_CLOSE);

   if(handleEmaFast == INVALID_HANDLE || handleEmaSlow == INVALID_HANDLE || handleRsi == INVALID_HANDLE)
   {
      Print("Erreur lors de la creation des handles.");
      return(INIT_FAILED);
   }

   startingDailyEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   trade.SetExpertMagicNumber(123456);

   Print("AZIZ BOT V1 initialise avec succes.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleEmaFast);
   IndicatorRelease(handleEmaSlow);
   IndicatorRelease(handleRsi);
}

void OnTick()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != lastTradeDay)
   {
      startingDailyEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      consecutiveLosses = 0;
      lastTradeDay = dt.day;
   }

   if(!CheckRiskLimits()) return;

   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   CheckLastTradeResult();

   if(PositionsTotal() >= InpMaxOpenPositions) return;

   double emaFast[], emaSlow[], rsi[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleEmaFast, 0, 1, 2, emaFast) < 2 ||
      CopyBuffer(handleEmaSlow, 0, 1, 2, emaSlow) < 2 ||
      CopyBuffer(handleRsi, 0, 1, 2, rsi) < 2)
   {
      return;
   }

   bool isTrendUp   = (emaFast[0] > emaSlow[0]);
   bool isTrendDown = (emaFast[0] < emaSlow[0]);

   if(isTrendUp && rsi[0] <= InpRsiOversold && iClose(_Symbol, PERIOD_M15, 1) > iOpen(_Symbol, PERIOD_M15, 1))
   {
      ExecuteOrder(ORDER_TYPE_BUY);
   }
   else if(isTrendDown && rsi[0] >= InpRsiOverbought && iClose(_Symbol, PERIOD_M15, 1) < iOpen(_Symbol, PERIOD_M15, 1))
   {
      ExecuteOrder(ORDER_TYPE_SELL);
   }
}

bool CheckRiskLimits()
{
   if(consecutiveLosses >= InpMaxConsecLosses) return false;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPercent = ((startingDailyEquity - currentEquity) / startingDailyEquity) * 100.0;
   if(dailyLossPercent >= InpMaxDailyLossPct) return false;

   return true;
}

void ExecuteOrder(ENUM_ORDER_TYPE type)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = InpStopLossPips * _Point;
   double slPrice = (type == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;
   double tpPrice = (type == ORDER_TYPE_BUY) ? price + (InpTakeProfitPips * _Point) : price - (InpTakeProfitPips * _Point);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double lotSize = riskAmount / (InpStopLossPips * tickValue);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lotSize, _Symbol, price, slPrice, tpPrice, "AZIZ BOT V1 BUY");
   else if(type == ORDER_TYPE_SELL)
      trade.Sell(lotSize, _Symbol, price, slPrice, tpPrice, "AZIZ BOT V1 SELL");
}

void CheckLastTradeResult()
{
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   int totalTrades = HistoryDealsTotal();
   
   for(int i = totalTrades - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if(profit < 0)
            consecutiveLosses++;
         else if(profit > 0)
            consecutiveLosses = 0;
         break;
      }
   }
}0

