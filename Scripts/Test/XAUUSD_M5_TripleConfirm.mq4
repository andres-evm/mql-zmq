//+------------------------------------------------------------------+
//| XAUUSD M5 - Triple Confirm + TP/SL Dinámicos + MTF Confirm       |
//+------------------------------------------------------------------+
#property strict

// Valores para el parámetro price_field del Estocástico
#define STO_PRICE_LOWHIGH   0
#define STO_PRICE_CLOSECLOSE 1

//-------------------- Inputs de riesgo y control --------------------
input double   LotsPercent      = 10.0;    // % del balance por operación
input double   MaxExposure      = 50.0;    // % máximo del balance expuesto
input int      MagicNumber      = 123456;  // Identificador del EA
input bool     AllowLong        = true;
input bool     AllowShort       = true;

//-------------------- Inputs de indicadores M5 ----------------------
// Estocástico (14,3,3) Low/High, niveles 20/80
input int      Sto_K            = 14;
input int      Sto_D            = 3;
input int      Sto_Slowing      = 3;
input int      Sto_LevelLow     = 20;
input int      Sto_LevelHigh    = 80;

// MACD 12-26-9
input int      MACD_Fast        = 12;
input int      MACD_Slow        = 26;
input int      MACD_Signal      = 9;

// ADX 14
input int      ADX_Period       = 14;
input double   ADX_Thresh       = 20.0;

// Bollinger 20/2
input int      BB_Period        = 20;
input double   BB_Dev           = 2.0;

//-------------------- TP / SL Dinámicos -----------------------------
input int      ATR_Period       = 14;
input double   ATR_SL_Mult      = 1.5;     // SL = 1.5 * ATR
input double   ATR_TP_Mult      = 2.0;     // TP base = 2 * ATR

input int      StdDev_Period    = 20;
input double   StdDev_Mult      = 1.0;     // TP candidato usando σ

//-------------------- Break-even y Chandelier -----------------------
input double   BE_ATR_Mult      = 0.5;     // BE al ganar 0.5 * ATR
input int      Chand_Period     = 22;      // N velas para Chandelier
input double   Chand_ATR_Mult   = 2.5;     // k * ATR para Chandelier

//-------------------- Confirmación Multi–Timeframe ------------------
input bool     Use_MTF_Confirm  = true;
input ENUM_TIMEFRAMES MTF_TF    = PERIOD_H1;
input double   MTF_ADX_Thresh   = 20.0;

//-------------------- Variables globales ----------------------------
static datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Cuenta cuántas órdenes abiertas tiene el EA en este símbolo      |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            count++;
      }
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Manejo de Break-even y Chandelier Exit                           |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   RefreshRates();

   double atrNow = iATR(NULL, 0, ATR_Period, 0);
   if(atrNow <= 0) return;

   double stopLevelPoints = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;

      int    type      = OrderType();
      double openPrice = OrderOpenPrice();
      double sl        = OrderStopLoss();
      double tp        = OrderTakeProfit();

      if(type != OP_BUY && type != OP_SELL)
         continue;

      if(type == OP_BUY)
      {
         double currentBid = Bid;
         double profitDist = currentBid - openPrice;

         // Break-even
         if(profitDist > BE_ATR_Mult * atrNow && (sl < openPrice || sl == 0))
         {
            double newSL = openPrice;
            if(stopLevelPoints > 0 && (currentBid - newSL) < stopLevelPoints)
               newSL = currentBid - stopLevelPoints;
            newSL = NormalizeDouble(newSL, Digits);

            if(newSL > sl)
            {
               if(!OrderModify(OrderTicket(), openPrice, newSL, tp, 0, clrBlue))
                  Print("Error BE BUY: ", GetLastError());
               else
                  sl = newSL;
            }
         }

         // Chandelier Exit (sobre últimos Chand_Period máximos)
         int highestIndex = iHighest(NULL, 0, MODE_HIGH, Chand_Period, 1);
         double highest   = iHigh(NULL, 0, highestIndex);
         double chandSL   = highest - Chand_ATR_Mult * atrNow;

         if(stopLevelPoints > 0 && (currentBid - chandSL) < stopLevelPoints)
            chandSL = currentBid - stopLevelPoints;

         chandSL = NormalizeDouble(chandSL, Digits);

         if(chandSL > sl && chandSL < currentBid)
         {
            if(!OrderModify(OrderTicket(), openPrice, chandSL, tp, 0, clrBlue))
               Print("Error Chandelier BUY: ", GetLastError());
         }
      }
      else if(type == OP_SELL)
      {
         double currentAsk = Ask;
         double profitDist = openPrice - currentAsk;

         // Break-even
         if(profitDist > BE_ATR_Mult * atrNow && (sl > openPrice || sl == 0))
         {
            double newSL = openPrice;
            if(stopLevelPoints > 0 && (newSL - currentAsk) < stopLevelPoints)
               newSL = currentAsk + stopLevelPoints;
            newSL = NormalizeDouble(newSL, Digits);

            if(newSL < sl || sl == 0)
            {
               if(!OrderModify(OrderTicket(), OrderOpenPrice(), newSL, tp, 0, clrRed))
                  Print("Error BE SELL: ", GetLastError());
               else
                  sl = newSL;
            }
         }

         // Chandelier Exit (sobre últimos Chand_Period mínimos)
         int lowestIndex = iLowest(NULL, 0, MODE_LOW, Chand_Period, 1);
         double lowest   = iLow(NULL, 0, lowestIndex);
         double chandSL  = lowest + Chand_ATR_Mult * atrNow;

         if(stopLevelPoints > 0 && (chandSL - currentAsk) < stopLevelPoints)
            chandSL = currentAsk + stopLevelPoints;

         chandSL = NormalizeDouble(chandSL, Digits);

         if((sl == 0 || chandSL < sl) && chandSL > currentAsk)
         {
            if(!OrderModify(OrderTicket(), OrderOpenPrice(), chandSL, tp, 0, clrRed))
               Print("Error Chandelier SELL: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cálculo de lote dinámico según 10% del balance y MaxExposure     |
//+------------------------------------------------------------------+
double ComputeLotSize(double marginPerLot, double balance)
{
   double riskFrac = LotsPercent / 100.0;
   double lotSize  = 0.0;

   if(marginPerLot > 0.0)
      lotSize = (balance * riskFrac) / marginPerLot;
   else
      lotSize = (balance * riskFrac) / 1000.0;

   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);

   if(lotStep <= 0) lotStep = 0.01;

   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M5)
      Print("ADVERTENCIA: EA optimizado para XAUUSD en M5.");

   lastBarTime = iTime(NULL, PERIOD_M5, 0);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1) Gestión de posiciones abiertas (BE + Chandelier) en cada tick
   ManageOpenTrades();

   // 2) Solo evaluar nuevas entradas cuando haya nueva vela M5 cerrada
   datetime currentBarTime = iTime(NULL, PERIOD_M5, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   if(Bars < 100) return;

   RefreshRates();

   int shift = 1; // vela recién cerrada

   //---------------- INDICADORES M5 ----------------

   // Estocástico (14,3,3) Low/High
   double stochK_prev2 = iStochastic(NULL, 0, Sto_K, Sto_D, Sto_Slowing,
                                     MODE_SMA, STO_PRICE_LOWHIGH, MODE_MAIN,   shift+1);
   double stochD_prev2 = iStochastic(NULL, 0, Sto_K, Sto_D, Sto_Slowing,
                                     MODE_SMA, STO_PRICE_LOWHIGH, MODE_SIGNAL, shift+1);
   double stochK_prev1 = iStochastic(NULL, 0, Sto_K, Sto_D, Sto_Slowing,
                                     MODE_SMA, STO_PRICE_LOWHIGH, MODE_MAIN,   shift);
   double stochD_prev1 = iStochastic(NULL, 0, Sto_K, Sto_D, Sto_Slowing,
                                     MODE_SMA, STO_PRICE_LOWHIGH, MODE_SIGNAL, shift);

   bool stochBuySignal  = (stochK_prev2 < stochD_prev2 &&
                           stochK_prev1 > stochD_prev1 &&
                           stochK_prev2 < Sto_LevelLow);

   bool stochSellSignal = (stochK_prev2 > stochD_prev2 &&
                           stochK_prev1 < stochD_prev1 &&
                           stochK_prev2 > Sto_LevelHigh);

   // MACD histograma (OsMA)
   double macdHist_prev2 = iOsMA(NULL, 0, MACD_Fast, MACD_Slow, MACD_Signal,
                                 PRICE_CLOSE, shift+1);
   double macdHist_prev1 = iOsMA(NULL, 0, MACD_Fast, MACD_Slow, MACD_Signal,
                                 PRICE_CLOSE, shift);

   bool macdBuySignal  = (macdHist_prev2 < 0.0 && macdHist_prev1 > 0.0);
   bool macdSellSignal = (macdHist_prev2 > 0.0 && macdHist_prev1 < 0.0);

   // ADX + DI en M5
   double adxValue   = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_MAIN,    shift);
   double adxDIPlus  = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_PLUSDI,  shift);
   double adxDIMinus = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, shift);

   bool adxTrend = (adxValue > ADX_Thresh);
   bool adxUp    = (adxDIPlus > adxDIMinus);
   bool adxDown  = (adxDIMinus > adxDIPlus);

   // Bollinger Bands
   double bbUpper = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, shift);
   double bbLower = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, shift);
   double closePrev  = iClose(NULL, 0, shift);
   double closePrev2 = iClose(NULL, 0, shift+1);

   bool nearLowerBand = (closePrev <= bbLower);
   bool nearUpperBand = (closePrev >= bbUpper);

   // Volumen direccional (vela verde/roja)
   bool volGreen = (closePrev >= closePrev2);
   bool volRed   = (closePrev <  closePrev2);

   // ATR y StdDev para TP/SL dinámicos
   double atrPrev = iATR(NULL, 0, ATR_Period, shift);
   double stdPrev = iStdDev(NULL, 0, StdDev_Period, 0, MODE_SMA, PRICE_CLOSE, shift);

   if(atrPrev <= 0 || stdPrev <= 0)
      return;

   // Pivotes diarios (del día anterior)
   double highD1  = iHigh(NULL, PERIOD_D1, 1);
   double lowD1   = iLow (NULL, PERIOD_D1, 1);
   double closeD1 = iClose(NULL, PERIOD_D1, 1);
   double pivotP  = (highD1 + lowD1 + closeD1) / 3.0;
   double pivotR1 = 2.0 * pivotP - lowD1;
   double pivotS1 = 2.0 * pivotP - highD1;

   //---------------- Confirmación MTF (H1) ----------------
   bool mtfBuyOK  = true;
   bool mtfSellOK = true;

   if(Use_MTF_Confirm)
   {
      double adxMTF    = iADX(NULL, MTF_TF, ADX_Period, PRICE_CLOSE, MODE_MAIN,    1);
      double diPlusMTF = iADX(NULL, MTF_TF, ADX_Period, PRICE_CLOSE, MODE_PLUSDI,  1);
      double diMinusMTF= iADX(NULL, MTF_TF, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);

      mtfBuyOK  = (adxMTF > MTF_ADX_Thresh && diPlusMTF > diMinusMTF);
      mtfSellOK = (adxMTF > MTF_ADX_Thresh && diMinusMTF > diPlusMTF);
   }

   //---------------- Señales finales BUY / SELL ----------------

   bool canBuy  = AllowLong  &&
                  stochBuySignal &&
                  macdBuySignal &&
                  adxTrend && adxUp &&
                  volGreen && nearLowerBand &&
                  mtfBuyOK;

   bool canSell = AllowShort &&
                  stochSellSignal &&
                  macdSellSignal &&
                  adxTrend && adxDown &&
                  volRed && nearUpperBand &&
                  mtfSellOK;

   //---------------- Gestión de riesgo y número de órdenes -----

   int    openTrades   = CountOpenTrades();
   double balance      = AccountBalance();
   double marginPerLot = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
   double lotSize      = ComputeLotSize(marginPerLot, balance);
   double currentMargin= AccountMargin();
   double newTradeMargin = (marginPerLot > 0 ? marginPerLot * lotSize : balance * (LotsPercent/100.0));

   bool underMaxExposure = ((currentMargin + newTradeMargin) <= (MaxExposure/100.0 * balance));

   double stopLevelPoints = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   int    slippage        = 5;

   //---------------- Entrada BUY --------------------------------
   if(canBuy && openTrades < 3 && underMaxExposure)
   {
      double entryPrice = NormalizeDouble(Ask, Digits);

      double slPrice = entryPrice - ATR_SL_Mult * atrPrev;

      double tpCandidates[3];
      int    n = 0;

      double tpAtr = entryPrice + ATR_TP_Mult * atrPrev;
      double tpStd = entryPrice + StdDev_Mult * stdPrev;

      if(tpAtr > entryPrice) tpCandidates[n++] = tpAtr;
      if(tpStd > entryPrice) tpCandidates[n++] = tpStd;
      if(pivotR1 > entryPrice) tpCandidates[n++] = pivotR1;

      double tpPrice;
      if(n > 0)
      {
         tpPrice = tpCandidates[0];
         for(int i=1; i<n; i++)
         {
            if(MathAbs(tpCandidates[i] - entryPrice) < MathAbs(tpPrice - entryPrice))
               tpPrice = tpCandidates[i];
         }
      }
      else
      {
         tpPrice = entryPrice + ATR_TP_Mult * atrPrev;
      }

      if(stopLevelPoints > 0)
      {
         if(MathAbs(entryPrice - slPrice) < stopLevelPoints)
            slPrice = entryPrice - stopLevelPoints;
         if(MathAbs(tpPrice - entryPrice) < stopLevelPoints)
            tpPrice = entryPrice + stopLevelPoints;
      }

      slPrice = NormalizeDouble(slPrice, Digits);
      tpPrice = NormalizeDouble(tpPrice, Digits);

      int ticket = OrderSend(Symbol(), OP_BUY, lotSize, entryPrice, slippage,
                             slPrice, tpPrice, "XAU M5 BUY", MagicNumber, 0, clrGreen);
      if(ticket < 0)
         Print("Error al abrir BUY: ", GetLastError());
      else
         Print("BUY abierto: lote=", lotSize, " SL=", slPrice, " TP=", tpPrice);
   }

   //---------------- Entrada SELL -------------------------------
   if(canSell && openTrades < 3 && underMaxExposure)
   {
      double entryPrice = NormalizeDouble(Bid, Digits);

      double slPrice = entryPrice + ATR_SL_Mult * atrPrev;

      double tpCandidates[3];
      int    n = 0;

      double tpAtr = entryPrice - ATR_TP_Mult * atrPrev;
      double tpStd = entryPrice - StdDev_Mult * stdPrev;

      if(tpAtr < entryPrice) tpCandidates[n++] = tpAtr;
      if(tpStd < entryPrice) tpCandidates[n++] = tpStd;
      if(pivotS1 < entryPrice) tpCandidates[n++] = pivotS1;

      double tpPrice;
      if(n > 0)
      {
         tpPrice = tpCandidates[0];
         for(int i=1; i<n; i++)
         {
            if(MathAbs(entryPrice - tpCandidates[i]) < MathAbs(entryPrice - tpPrice))
               tpPrice = tpCandidates[i];
         }
      }
      else
      {
         tpPrice = entryPrice - ATR_TP_Mult * atrPrev;
      }

      if(stopLevelPoints > 0)
      {
         if(MathAbs(slPrice - entryPrice) < stopLevelPoints)
            slPrice = entryPrice + stopLevelPoints;
         if(MathAbs(entryPrice - tpPrice) < stopLevelPoints)
            tpPrice = entryPrice - stopLevelPoints;
      }

      slPrice = NormalizeDouble(slPrice, Digits);
      tpPrice = NormalizeDouble(tpPrice, Digits);

      int ticket = OrderSend(Symbol(), OP_SELL, lotSize, entryPrice, slippage,
                             slPrice, tpPrice, "XAU M5 SELL", MagicNumber, 0, clrRed);
      if(ticket < 0)
         Print("Error al abrir SELL: ", GetLastError());
      else
         Print("SELL abierto: lote=", lotSize, " SL=", slPrice, " TP=", tpPrice);
   }
}
//+------------------------------------------------------------------+
