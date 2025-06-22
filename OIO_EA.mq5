//+------------------------------------------------------------------+
//|                                                       OIO_EA.mq5 |
//|                        Copyright 2023, 你的名字或公司名 |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>

#property copyright "Copyright 2023, 你的名字或公司名"
#property link      "https://www.example.com"
#property version   "1.00"
#property strict    // 严格模式，有助于代码质量

//--- 输入参数
// 一般来说，我们会把一些可调参数放在这里，但根据README，很多是动态计算的
// 为了简单起见，我们暂时不添加可配置的输入参数，后续可以根据需要添加

//--- 全局变量
// OIO 结构相关变量
double oio_high = 0;         // OIO结构的最高价
double oio_low = 0;          // OIO结构的最低价
double oio_mid = 0;          // OIO结构的中点
datetime oio_bar_time = 0;   // OIO结构第三根K线的开盘时间，用于标识OIO结构

// 订单票据
ulong buy_stop_limit_ticket = 0;    // 多单限价单票据 (ulong for MQL5 order tickets)
ulong sell_stop_limit_ticket = 0;   // 空单限价单票据 (ulong for MQL5 order tickets)
ulong second_buy_limit_ticket = 0;  // 第二张多单限价单票据 (ulong for MQL5 order tickets)
ulong second_sell_limit_ticket = 0; // 第二张空单限价单票据 (ulong for MQL5 order tickets)

ulong first_order_ticket = 0;      // 记录第一张被触发的订单的票据 (ulong for MQL5 position/order tickets)
int first_order_type = -1;        // 记录第一张被触发的订单类型 (POSITION_TYPE_BUY 或 POSITION_TYPE_SELL)


//+------------------------------------------------------------------+
//| EA初始化函数                                                      |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 初始化注释
   Print("OIO EA 初始化...");
   Print("EA版本: ", __FILE__, " ", __DATE__, " ", TimeToString(TimeCurrent(), TIME_SECONDS));
   Print("策略：OIO (Outside-Inside-Outside)");

   //--- 检查交易手数，这里默认为1手，后续可以改为输入参数
   if(1 <= 0) // 这里的 AccountInfoDouble(ACCOUNT_LOT_STEP) * N 比较复杂，暂时简化
     {
      Print("手数设置错误!");
      return(INIT_FAILED);
     }

   //--- 其他初始化代码可以放在这里

   Print("OIO EA 初始化完成.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| EA去初始化函数                                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- 去初始化注释
   Print("OIO EA 去初始化... 原因代码: ", reason);

   //--- 清理工作
   // 例如，删除图表对象，关闭未处理的订单等
   // 如果有限价单尚未触发，可以考虑在这里删除
   if(buy_stop_limit_ticket > 0)
     {
      OrderDelete(buy_stop_limit_ticket);
      Print("删除未触发的多单限价单 #", buy_stop_limit_ticket);
     }
   if(sell_stop_limit_ticket > 0)
     {
      OrderDelete(sell_stop_limit_ticket);
      Print("删除未触发的空单限价单 #", sell_stop_limit_ticket);
     }
   if(second_buy_limit_ticket > 0)
     {
      OrderDelete(second_buy_limit_ticket);
      Print("删除未触发的第二张多单限价单 #", second_buy_limit_ticket);
     }
   if(second_sell_limit_ticket > 0)
     {
      OrderDelete(second_sell_limit_ticket);
      Print("删除未触发的第二张空单限价单 #", second_sell_limit_ticket);
     }

   // 删除图表上的OIO标记对象 (如果存在)
   ObjectDelete(0, "OIO_Rectangle");


   Print("OIO EA 去初始化完成.");
  }
//+------------------------------------------------------------------+
//| EA tick处理函数                                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- EA的主要逻辑将在这里实现
   // 1. 检查是否有新的K线形成
   // 2. 识别OIO结构
   // 3. 管理订单

   //--- EA的主要逻辑将在这里实现
   // 1. 检查是否有新的K线形成
   // 2. 识别OIO结构
   // 3. 管理订单

   // 检查是否有新的K线，避免在同一根K线上重复操作
   static datetime prevBarTime = 0;
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   if(prevBarTime == currentBarTime && prevBarTime != 0) // 如果 prevBarTime 为 0 (第一次运行)，则继续
     {
      return; // 不是新K线，直接返回
     }
   prevBarTime = currentBarTime;

   // 识别OIO结构
   if(first_order_ticket == 0 && buy_stop_limit_ticket == 0 && sell_stop_limit_ticket == 0) // 只有在没有已触发订单或现有挂单时才检测新的OIO
     {
      DetectOIO();
     }

   // 订单管理逻辑将在 OnTrade() 和 OnTick() 中根据需要进一步实现
  }
//+------------------------------------------------------------------+
//| 交易事件处理函数                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {
   //--- 当交易活动发生时（如下单、平仓、修改订单等），此函数会被调用
   // 我们将在这里处理订单触发后的逻辑，例如取消另一张限价单，设置第二张订单等
   CAccountInfo account;
   CTrade trade;
   trade.SetExpertMagicNumber(12345); // 确保只处理本EA的订单
   trade.SetTypeFillingBySymbol(_Symbol);

   // 检查是否有挂单被触发成为持仓
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong order_ticket = OrderGetTicket(i);
      if(OrderSelect(order_ticket))
        {
         // 检查是否是我们的初始限价单之一被部分或完全成交，成为了一个市场订单
         // 注意：一个限价单成交后，它会从挂单列表消失，变成一个持仓。
         // OnTrade事件会在订单状态改变时触发。
         // 我们需要检查的场景是：一个挂单消失了，同时出现了一个新的持仓。
         // 或者更简单地，检查我们的挂单票据是否还存在。
         // 如果挂单票据对应的订单不存在了，说明它可能被触发或取消。
         // 我们需要查询历史订单来确认它是否被触发。

         // 这个逻辑比较复杂，因为OnTrade会被多种事件触发。
         // 一个更可靠的方法是检查 Position 列表。
      }
     }

   // 检查当前持仓情况
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionSelect(_Symbol)) // 选择当前品种的持仓
        {
         if(PositionGetInteger(POSITION_MAGIC) == 12345 && PositionGetInteger(POSITION_TICKET) != first_order_ticket) // 是我们的EA的订单, 且不是已记录的first_order
           {
            // 这是一个新触发的订单
            if(first_order_ticket == 0) // 这是第一个被触发的订单
              {
               first_order_ticket = PositionGetInteger(POSITION_TICKET);
               first_order_type = (int)PositionGetInteger(POSITION_TYPE); // POSITION_TYPE_BUY or POSITION_TYPE_SELL

               Print("第一张订单 #", first_order_ticket, " 已触发. 类型: ", (first_order_type == POSITION_TYPE_BUY ? "Buy" : "Sell"));

               if(first_order_type == POSITION_TYPE_BUY)
                 {
                  // 多单触发，取消空单限价单
                  if(sell_stop_limit_ticket != 0)
                    {
                     Print("多单已触发，尝试取消空单限价单 #", sell_stop_limit_ticket);
                     if(OrderDelete(sell_stop_limit_ticket))
                       {
                        Print("空单限价单 #", sell_stop_limit_ticket, " 已成功取消.");
                       }
                     else
                       {
                        Print("空单限价单 #", sell_stop_limit_ticket, " 取消失败 (可能已被触发或不存在).");
                       }
                     sell_stop_limit_ticket = 0; // 清除票据
                    }
                  // 设置第二张多单
                  SetupSecondOrder(ORDER_TYPE_BUY);
                 }
               else if(first_order_type == POSITION_TYPE_SELL)
                 {
                  // 空单触发，取消多单限价单
                  if(buy_stop_limit_ticket != 0)
                    {
                     Print("空单已触发，尝试取消多单限价单 #", buy_stop_limit_ticket);
                     if(OrderDelete(buy_stop_limit_ticket))
                       {
                        Print("多单限价单 #", buy_stop_limit_ticket, " 已成功取消.");
                       }
                     else
                       {
                        Print("多单限价单 #", buy_stop_limit_ticket, " 取消失败 (可能已被触发或不存在).");
                       }
                     buy_stop_limit_ticket = 0; // 清除票据
                    }
                  // 设置第二张空单
                  SetupSecondOrder(ORDER_TYPE_SELL);
                 }
               // 一旦处理了一个新触发的订单，就跳出循环，避免重复处理或处理旧状态
               break;
              }
           }
        }
     }

   // 检查是否有订单关闭 (例如止盈或止损)
   // 这个逻辑也比较复杂，因为需要检查历史订单
   // 简化处理：如果 first_order_ticket != 0 但 PositionsTotal() 中找不到这个 ticket，说明它可能关闭了
   if(first_order_ticket != 0)
     {
      bool first_order_still_open = PositionSelectByTicket(first_order_ticket);
      double first_order_profit = 0;
      ENUM_DEAL_REASON first_order_close_reason = (ENUM_DEAL_REASON)0; // 使用 DEAL_REASON_UNKNOWN 的数值

      if(!first_order_still_open) // 如果第一单已经不在持仓中
        {
         // 尝试从历史订单中获取关闭原因和盈利情况
         if(HistorySelect(0, TimeCurrent())) // 选择所有历史订单
           {
            for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
              {
               ulong deal_ticket = HistoryDealGetTicket(i);
               if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT && // 是平仓交易
                  HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID) == (ulong)first_order_ticket && // 对应第一单的position ID
                  HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == 12345)
                 {
                  first_order_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                  first_order_close_reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
                  Print("历史记录: 第一张订单 #", first_order_ticket, " 已关闭. 盈利: ", first_order_profit, ", 原因: ", EnumToString(first_order_close_reason));
                  break;
                 }
              }
           }

         Print("第一张订单 #", first_order_ticket, " 已关闭.");
         // 如果第一张订单止盈,且第二张订单未触发，则取消第二张订单
         bool first_order_was_tp = (first_order_close_reason == DEAL_REASON_TP);
         Print("第一张订单是否止盈: ", first_order_was_tp);

         if(first_order_was_tp)
           {
            if(second_buy_limit_ticket != 0 && OrderSelect(second_buy_limit_ticket) && OrderGetInteger(ORDER_STATE) == ORDER_STATE_PLACED)
              {
               Print("第一张订单止盈，取消未触发的第二张多单限价单 #", second_buy_limit_ticket);
               OrderDelete(second_buy_limit_ticket);
               second_buy_limit_ticket = 0;
              }
            if(second_sell_limit_ticket != 0 && OrderSelect(second_sell_limit_ticket) && OrderGetInteger(ORDER_STATE) == ORDER_STATE_PLACED)
              {
               Print("第一张订单止盈，取消未触发的第二张空单限价单 #", second_sell_limit_ticket);
               OrderDelete(second_sell_limit_ticket);
               second_sell_limit_ticket = 0;
              }
           }
         // 无论第一单是否止盈，只要它关闭了，整个OIO周期就结束了，重置状态
         ResetOOOState();
        }
      else // 第一单仍然持仓
        {
         // 检查第二张订单是否已触发
         bool second_buy_active = IsOrderActive(second_buy_limit_ticket);
         bool second_sell_active = IsOrderActive(second_sell_limit_ticket);

         if((first_order_type == POSITION_TYPE_BUY && second_buy_active) || (first_order_type == POSITION_TYPE_SELL && second_sell_active))
           {
            Print("第一张订单未止盈，且第二张订单已触发。调整止盈价格。");
            AdjustTPForBothOrders();
           }
        }
     }
}


//+------------------------------------------------------------------+
//| 调整两笔订单的止盈价格                                             |
//+------------------------------------------------------------------+
void AdjustTPForBothOrders()
  {
   if(first_order_ticket == 0) return;
   if(second_buy_limit_ticket == 0 && second_sell_limit_ticket == 0) return; // 没有第二单的票据（即使已激活）

   ulong active_second_order_ticket = (first_order_type == POSITION_TYPE_BUY) ? second_buy_limit_ticket : second_sell_limit_ticket; // 修改为 ulong
   if(!IsOrderActive(active_second_order_ticket)) // 确保第二单也是激活的持仓
     {
      Print("尝试调整止盈，但第二单 #", active_second_order_ticket, " 不是活动持仓。");
      return;
     }

   // 获取两笔订单的开仓价格和手数
   double price1=0, price2=0;
   double vol1=0, vol2=0;

   if(PositionSelectByTicket(first_order_ticket))
     {
      price1 = PositionGetDouble(POSITION_PRICE_OPEN);
      vol1 = PositionGetDouble(POSITION_VOLUME);
     }
   else
     {
      Print("无法获取第一张订单 #", first_order_ticket, " 的信息以调整TP。");
      return;
     }

   if(PositionSelectByTicket(active_second_order_ticket))
     {
      price2 = PositionGetDouble(POSITION_PRICE_OPEN);
      vol2 = PositionGetDouble(POSITION_VOLUME);
     }
   else
     {
      Print("无法获取第二张订单 #", active_second_order_ticket, " 的信息以调整TP。");
      return;
     }

   if(vol1 == 0 || vol2 == 0)
     {
      Print("订单手数为0，无法计算平均成本价。");
      return;
     }

   double avg_cost_price = (price1 * vol1 + price2 * vol2) / (vol1 + vol2);
   avg_cost_price = NormalizeDouble(avg_cost_price, _Digits);
   Print("计算得到的平均成本价: ", DoubleToString(avg_cost_price, _Digits));

   double tick_size = GetTickSize();
   double new_tp_price;

   // 修改止盈
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_SLTP;
   request.symbol = _Symbol;
   request.magic = 12345;


   if(first_order_type == POSITION_TYPE_BUY) // 两笔都是多单
     {
      new_tp_price = NormalizeDouble(avg_cost_price + 3 * tick_size, _Digits);
      Print("调整为多单统一止盈价: ", DoubleToString(new_tp_price, _Digits));
      // 修改第一单止盈
      request.position = (ulong)first_order_ticket;
      request.tp = new_tp_price;
      request.sl = PositionGetDouble(POSITION_SL); // SL保持不变
      if(!OrderSend(request, result))
         Print("修改第一张订单 #", first_order_ticket, " TP失败: ", GetLastError());
      else
         Print("修改第一张订单 #", first_order_ticket, " TP成功. Retcode: ", result.retcode);

      // 修改第二单止盈
      request.position = (ulong)active_second_order_ticket;
      request.tp = new_tp_price;
      request.sl = PositionGetDouble(POSITION_SL); // SL保持不变
      if(!OrderSend(request, result))
         Print("修改第二张订单 #", active_second_order_ticket, " TP失败: ", GetLastError());
      else
         Print("修改第二张订单 #", active_second_order_ticket, " TP成功. Retcode: ", result.retcode);
     }
   else if(first_order_type == POSITION_TYPE_SELL) // 两笔都是空单
     {
      new_tp_price = NormalizeDouble(avg_cost_price - 3 * tick_size, _Digits);
      Print("调整为空单统一止盈价: ", DoubleToString(new_tp_price, _Digits));
      // 修改第一单止盈
      request.position = (ulong)first_order_ticket;
      request.tp = new_tp_price;
      request.sl = PositionGetDouble(POSITION_SL); // SL保持不变
      if(!OrderSend(request, result))
         Print("修改第一张订单 #", first_order_ticket, " TP失败: ", GetLastError());
      else
         Print("修改第一张订单 #", first_order_ticket, " TP成功. Retcode: ", result.retcode);

      // 修改第二单止盈
      request.position = (ulong)active_second_order_ticket;
      request.tp = new_tp_price;
      request.sl = PositionGetDouble(POSITION_SL); // SL保持不变
      if(!OrderSend(request, result))
         Print("修改第二张订单 #", active_second_order_ticket, " TP失败: ", GetLastError());
      else
         Print("修改第二张订单 #", active_second_order_ticket, " TP成功. Retcode: ", result.retcode);
     }
  }

//+------------------------------------------------------------------+
//| 检查订单是否已成为活动持仓 (辅助函数)                             |
//+------------------------------------------------------------------+
bool IsOrderActive(long ticket)
  {
   if(ticket == 0) return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_TICKET) == ticket)
        {
         return true; // 订单是活动持仓
        }
     }
   return false; // 订单不是活动持仓 (可能是挂单或已关闭)
  }

//+------------------------------------------------------------------+
//| 重置OIO相关状态，以便进行下一次OIO检测                             |
//+------------------------------------------------------------------+
void ResetOOOState()
  {
   Print("重置OIO状态...");
   oio_high = 0;
   oio_low = 0;
   oio_mid = 0;
   // oio_bar_time 不在这里重置，DetectOIO会用它来避免重复处理同一根K线形成的OIO

   buy_stop_limit_ticket = 0;
   sell_stop_limit_ticket = 0;
   second_buy_limit_ticket = 0;
   second_sell_limit_ticket = 0;
   first_order_ticket = 0;
   first_order_type = -1;

   // 删除图表标记，因为OIO周期结束
   ObjectDelete(0, "OIO_Rectangle");
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| 设置第二张订单                                                    |
//+------------------------------------------------------------------+
void SetupSecondOrder(ENUM_ORDER_TYPE order_type) // order_type 是指第一张被触发的订单类型
  {
   // 确保OIO中点有效
   if(oio_mid == 0 || oio_high == 0 || oio_low == 0)
     {
      Print("OIO中点无效，无法设置第二张订单。");
      return;
     }

   // 确保第一张订单信息已记录
   if(first_order_ticket == 0)
     {
      Print("第一张订单信息未记录，无法设置第二张订单。");
      return;
     }

   double tick_size = GetTickSize();
   if(tick_size == 0)
     {
      Print("无法获取tick size，无法设置第二张订单。");
      return;
     }

   ulong magic_number = 12345; // EA的魔术数字
   double lot_size = 1.0;       // 根据README，固定1手
   double open_price = NormalizeDouble(oio_mid, _Digits); // 开仓价为OIO中点
   double sl_price;

   string comment = "";

   if(order_type == ORDER_TYPE_BUY) // 如果第一单是多单，则第二单也是多单
     {
      // 检查是否已存在第二张多单挂单
      if(second_buy_limit_ticket != 0)
        {
         Print("第二张多单限价单已存在或正在处理中。");
         return;
        }
      sl_price = NormalizeDouble(oio_low - tick_size, _Digits);
      comment = "OIO Buy Limit 2 (Mid)";
      Print("准备设置第二张多单: OP=", DoubleToString(open_price, _Digits), ", SL=", DoubleToString(sl_price, _Digits));
      bool placed = PlaceOrder(TRADE_ACTION_PENDING, _Symbol, lot_size, ORDER_TYPE_BUY_LIMIT, open_price, sl_price, 0, comment, magic_number, second_buy_limit_ticket); // TP暂时为0，后续可能调整
      if(placed)
        {
         Print("第二张多单限价单 #", second_buy_limit_ticket, " 已成功放置.");
        }
      else
        {
         Print("第二张多单限价单放置失败.");
         second_buy_limit_ticket = 0;
        }
     }
   else if(order_type == ORDER_TYPE_SELL) // 如果第一单是空单，则第二单也是空单
     {
      // 检查是否已存在第二张空单挂单
      if(second_sell_limit_ticket != 0)
        {
         Print("第二张空单限价单已存在或正在处理中。");
         return;
        }
      sl_price = NormalizeDouble(oio_high + tick_size, _Digits);
      comment = "OIO Sell Limit 2 (Mid)";
      Print("准备设置第二张空单: OP=", DoubleToString(open_price, _Digits), ", SL=", DoubleToString(sl_price, _Digits));
      bool placed = PlaceOrder(TRADE_ACTION_PENDING, _Symbol, lot_size, ORDER_TYPE_SELL_LIMIT, open_price, sl_price, 0, comment, magic_number, second_sell_limit_ticket); // TP暂时为0，后续可能调整
      if(placed)
        {
         Print("第二张空单限价单 #", second_sell_limit_ticket, " 已成功放置.");
        }
      else
        {
         Print("第二张空单限价单放置失败.");
         second_sell_limit_ticket = 0;
        }
     }
   else
     {
      Print("错误的订单类型传递给SetupSecondOrder: ", EnumToString(order_type));
     }
  }
//+------------------------------------------------------------------+
//| 图表事件处理函数                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   //--- 可以处理图表事件，例如点击按钮等，本EA暂时不需要
  }
//+------------------------------------------------------------------+
//| 定时器函数                                                      |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //--- 如果设置了定时器 (EventSetTimer), 此函数会定期执行
   // 本EA暂时不需要使用定时器
  }
//+------------------------------------------------------------------+
// --- 自定义函数区 ---
//+------------------------------------------------------------------+
//| 检测OIO结构                                                       |
//+------------------------------------------------------------------+
void DetectOIO()
  {
   // 获取最新的三根K线数据
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3)
     {
      Print("获取K线数据失败，K线数量不足3根。");
      return;
     }

   // rates[2] 是最新的K线 (bar 0)
   // rates[1] 是中间的K线 (bar 1)
   // rates[0] 是最老的K线 (bar 2)
   // 注意：MQL5中，CopyRates返回的数组，索引0是最旧的数据，索引N-1是最新的数据。
   // 因此，我们需要反过来看：
   // K线1: rates[0]
   // K线2: rates[1]
   // K线3: rates[2] (刚刚收盘的K线)

   double high1 = rates[0].high;
   double low1  = rates[0].low;
   double high2 = rates[1].high;
   double low2  = rates[1].low;
   double high3 = rates[2].high;
   double low3  = rates[2].low;

   // OIO结构条件判断
   // - 第1根和第3根K线的最高价都大于或等于第2根K线的最高价
   // - 第1根和第3根K线的最低价都小于或等于第2根K线的最低价
   bool isOIO = (high1 >= high2 && high3 >= high2 &&
                 low1 <= low2  && low3 <= low2);

   if(isOIO)
     {
      // 避免在同一个OIO结构上重复下单 (如果之前已经标记过)
      if(rates[2].time == oio_bar_time)
        {
         // Print("当前OIO结构 (基于K线 ", TimeToString(rates[2].time), ") 已被处理过。");
         return;
        }

      oio_bar_time = rates[2].time; // 记录OIO结构第三根K线的开盘时间

      // 计算OIO结构的高点、低点和中点
      oio_high = MathMax(high1, MathMax(high2, high3));
      oio_low  = MathMin(low1, MathMin(low2, low3));
      oio_mid  = (oio_high + oio_low) / 2.0;

      Print("检测到OIO结构!");
      Print("K线1 (", TimeToString(rates[0].time), "): H=", DoubleToString(high1, _Digits), ", L=", DoubleToString(low1, _Digits));
      Print("K线2 (", TimeToString(rates[1].time), "): H=", DoubleToString(high2, _Digits), ", L=", DoubleToString(low2, _Digits));
      Print("K线3 (", TimeToString(rates[2].time), "): H=", DoubleToString(high3, _Digits), ", L=", DoubleToString(low3, _Digits));
      Print("OIO 高点: ", DoubleToString(oio_high, _Digits),
            ", OIO 低点: ", DoubleToString(oio_low, _Digits),
            ", OIO 中点: ", DoubleToString(oio_mid, _Digits));

      // 在图表上标记OIO结构 (下一步实现)
      MarkOIOOnChart(rates[0].time, rates[2].time, oio_high, oio_low);

      // 设置限价单 (后续步骤实现)
      SetupLimitOrders();
     }
  }
//+------------------------------------------------------------------+
//| 在图表上标记OIO结构                                                |
//+------------------------------------------------------------------+
void MarkOIOOnChart(datetime time_start, datetime time_end, double price_high, double price_low)
  {
   string object_name = "OIO_Rectangle";
   // 删除旧的矩形（如果存在）
   ObjectDelete(0, object_name);

   // 创建矩形对象来标记OIO结构
   // 时间需要对应K线的开盘时间，价格对应高低点
   // 注意：time_end 是OIO结构中第三根K线的开盘时间，为了让矩形覆盖这三根K线，
   // 我们需要获取第三根K线的下一根K线的开盘时间作为矩形的右边界时间，
   // 或者简单地将宽度设置为3根K线。这里我们使用K线索引来定位时间。

   // 获取构成OIO的初始K线(rates[0])的索引
   int bar_index_start = iBarShift(_Symbol, _Period, time_start);
   // 获取构成OIO的结束K线(rates[2])的索引
   int bar_index_end = iBarShift(_Symbol, _Period, time_end);

   // MQL5中，时间轴从右向左增加索引，所以最新的K线索引是0
   // 因此，较早时间的K线有较大的索引值
   // 为了矩形能正确显示，time1应小于time2
   // time_start 是 rates[0].time, time_end 是 rates[2].time
   // 我们希望矩形从 rates[0] 的开盘时间横跨到 rates[2] 的收盘时间（即下一根K线的开盘时间）

   datetime rect_time_start = time_start; // OIO第一根K线的开盘时间
   datetime rect_time_end;

   // 获取第三根K线 (time_end) 之后一根K线的时间作为矩形的结束时间，以完整显示第三根K线
   MqlRates rate_after_oio3[];
   if(CopyRates(_Symbol, _Period, bar_index_end -1, 1, rate_after_oio3) == 1) // bar_index_end-1 是 rates[2] 之后的那根bar
     {
      rect_time_end = rate_after_oio3[0].time;
     }
   else // 如果无法获取下一根K线 (例如在最新的K线上)，则将结束时间设为当前K线的结束
     {
      // 对于这种情况，我们可以估算一个宽度，或者简单地让它在第三根K线的末尾结束
      // 为了简单，我们让它在第三根K线的开盘时间 + PeriodSeconds()
      rect_time_end = time_end + PeriodSeconds(_Period);
     }


   if(!ObjectCreate(0, object_name, OBJ_RECTANGLE, 0, rect_time_start, price_high, rect_time_end, price_low))
     {
      Print("创建OIO矩形失败! Error: ", GetLastError());
      return;
     }

   ObjectSetInteger(0, object_name, OBJPROP_COLOR, clrOrange);      // 设置颜色为橙色
   ObjectSetInteger(0, object_name, OBJPROP_STYLE, STYLE_SOLID);   // 设置样式为实线
   ObjectSetInteger(0, object_name, OBJPROP_WIDTH, 1);             // 设置线宽
   ObjectSetInteger(0, object_name, OBJPROP_BACK, true);           // 设置为背景对象，避免遮挡价格
   ObjectSetString(0, object_name, OBJPROP_TOOLTIP, "OIO Structure"); // 鼠标悬停提示

   Print("OIO结构已在图表上标记: ", object_name, " 从 ", TimeToString(rect_time_start), "到", TimeToString(rect_time_end));
   ChartRedraw(); // 刷新图表
  }
//+------------------------------------------------------------------+
//| 设置初始限价单                                                    |
//+------------------------------------------------------------------+
void SetupLimitOrders()
  {
   // 确保没有正在处理的订单或已设置的限价单
   if(buy_stop_limit_ticket != 0 || sell_stop_limit_ticket != 0 || first_order_ticket != 0)
     {
      Print("已有挂单或已触发订单，本次不设置新的OIO限价单。");
      return;
     }

   double tick_size = GetTickSize();
   if(tick_size == 0)
     {
      Print("无法获取tick size，无法设置订单。");
      return;
     }

   // 多单参数
   double buy_open_price = oio_high + tick_size;
   double buy_tp = buy_open_price + 3 * tick_size;
   double buy_sl = oio_low - tick_size;

   // 空单参数
   double sell_open_price = oio_low - tick_size;
   double sell_tp = sell_open_price - 3 * tick_size;
   double sell_sl = oio_high + tick_size;

   // 标准化价格，确保符合服务器要求的价格精度
   buy_open_price = NormalizeDouble(buy_open_price, _Digits);
   buy_tp = NormalizeDouble(buy_tp, _Digits);
   buy_sl = NormalizeDouble(buy_sl, _Digits);
   sell_open_price = NormalizeDouble(sell_open_price, _Digits);
   sell_tp = NormalizeDouble(sell_tp, _Digits);
   sell_sl = NormalizeDouble(sell_sl, _Digits);

   ulong magic_number = 12345; // EA的魔术数字，用于识别自己的订单
   double lot_size = 1.0;       // 根据README，固定1手

   Print("准备设置多单: OP=", DoubleToString(buy_open_price, _Digits), ", TP=", DoubleToString(buy_tp, _Digits), ", SL=", DoubleToString(buy_sl, _Digits));
   bool buy_placed = PlaceOrder(TRADE_ACTION_PENDING, _Symbol, lot_size, ORDER_TYPE_BUY_LIMIT, buy_open_price, buy_sl, buy_tp, "OIO Buy Limit 1", magic_number, buy_stop_limit_ticket);
   if(buy_placed)
     {
      Print("多单限价单 #", buy_stop_limit_ticket, " 已成功放置.");
     }
   else
     {
      Print("多单限价单放置失败.");
      buy_stop_limit_ticket = 0; // 重置票据
     }

   Print("准备设置空单: OP=", DoubleToString(sell_open_price, _Digits), ", TP=", DoubleToString(sell_tp, _Digits), ", SL=", DoubleToString(sell_sl, _Digits));
   bool sell_placed = PlaceOrder(TRADE_ACTION_PENDING, _Symbol, lot_size, ORDER_TYPE_SELL_LIMIT, sell_open_price, sell_sl, sell_tp, "OIO Sell Limit 1", magic_number, sell_stop_limit_ticket);
   if(sell_placed)
     {
      Print("空单限价单 #", sell_stop_limit_ticket, " 已成功放置.");
     }
   else
     {
      Print("空单限价单放置失败.");
      sell_stop_limit_ticket = 0; // 重置票据
     }

   // 如果任何一个订单放置失败，为了安全起见，可以考虑删除另一个已成功的订单
   // 但这里我们假设如果一个失败，另一个可能也因为类似原因失败，或者用户会介入
   // 简单处理：如果两个都失败了，那么下次OIO还会尝试。如果一个成功一个失败，那么EA会等待那个成功的单子。
  }
//+------------------------------------------------------------------+
// 后续步骤中定义的函数将放在这里
//+------------------------------------------------------------------+

// --- MQL5 spécifique pour les ordres ---
// MQL5 使用 MqlTradeRequest 和 MqlTradeResult 结构来发送交易请求
// 我们需要一个辅助函数来简化订单发送过程

/**
 * @brief 发送交易订单的辅助函数
 * @param action 交易类型 (TRADE_ACTION_PENDING, TRADE_ACTION_SLTP, etc.)
 * @param symbol 交易品种
 * @param volume 手数
 * @param type 订单类型 (ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_SELL_LIMIT, etc.)
 * @param price 开仓价格
 * @param sl 止损价格
 * @param tp 止盈价格
 * @param comment 订单注释
 * @param magic 魔术数字
 * @param ticket_var 用于存储订单票据的变量引用
 * @return bool 是否成功发送请求 (注意，这不代表订单一定成功执行)
 */
bool PlaceOrder(ENUM_TRADE_REQUEST_ACTIONS trade_action_param, string symbol, double volume, ENUM_ORDER_TYPE type, double price, double sl, double tp, string comment, ulong magic, ulong &ticket_var)
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = trade_action_param; // 使用修改后的参数名
   request.symbol   = symbol;
   request.volume   = volume;
   request.type     = type;
   request.price    = NormalizeDouble(price, _Digits);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= 5; // 允许的点差滑点
   request.magic    = magic;
   request.comment  = comment;
   request.type_filling = ORDER_FILLING_FOK; // 成交类型，FOK 或 IOC
   request.type_time    = ORDER_TIME_GTC;    // 订单有效期类型

   if(!OrderSend(request, result))
     {
      Print("OrderSend 失败. 返回代码: ", result.retcode, ", GetLastError(): ", GetLastError()); // 移除了 ErrorDescription, 添加 result.retcode
      Print("请求参数: action=", EnumToString(request.action), ", symbol=", symbol, ", volume=", volume, ", type=", EnumToString(type),
            ", price=", DoubleToString(price, _Digits), ", sl=", DoubleToString(sl, _Digits), ", tp=", DoubleToString(tp, _Digits));
      ticket_var = 0;
      return false;
     }

   // 对于挂单 (TRADE_ACTION_PENDING), 成功的 retcode 是 TRADE_RETCODE_PLACED
   // 对于市价单成交或SL/TP修改 (TRADE_ACTION_SLTP, TRADE_ACTION_MODIFY), 成功是 TRADE_RETCODE_DONE
   if(result.retcode == TRADE_RETCODE_PLACED || result.retcode == TRADE_RETCODE_DONE)
     {
      Print("订单 #", result.order, " ", comment, " 已成功发送/放置/执行. Retcode: ", result.retcode);
      ticket_var = result.order; // ulong to ulong, no data loss
      return true;
     }
   else
     {
      Print("订单发送成功，但未成功执行. 返回代码: ", result.retcode, " (", TradeRetcodeToString(result.retcode), ")");
      Print("OrderSend 错误详情: ", result.comment);
      ticket_var = 0;
      return false;
     }
  }

/**
 * @brief 取消/删除订单的辅助函数
 * @param ticket 要删除的订单票据
 * @return bool 是否成功发送删除请求
 */
bool OrderDelete(ulong ticket) // 修改参数类型为 ulong
  {
   if(ticket == 0) return false; // ulong 比较对象是 0

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_REMOVE; // 删除挂单
   request.order  = ticket;

   if(!OrderSend(request, result))
     {
      Print("OrderDelete 发送请求失败 for ticket #", ticket, ". Error Retcode: ", result.retcode, ", GetLastError(): ", GetLastError()); // 移除了 ErrorDescription
      return false;
     }

   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_REJECT) // REJECT can also mean it was already removed or filled
     {
      Print("订单 #", ticket, " 删除请求已处理. Retcode: ", result.retcode);
      // 如果是REJECT，可能订单已经被触发或者手动删除了，也算作“尝试删除完成”
      return true;
     }
   else
     {
      Print("订单 #", ticket, " 删除失败. Retcode: ", result.retcode, " (", TradeRetcodeToString(result.retcode), ")");
      return false;
     }
  }

// 将 TradeRetcode 转换为字符串的辅助函数
string TradeRetcodeToString(int retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_REQUOTE:          return "Requote";
      case TRADE_RETCODE_REJECT:           return "Reject";
      case TRADE_RETCODE_CANCEL:           return "Cancel";
      case TRADE_RETCODE_PLACED:           return "Placed";
      case TRADE_RETCODE_DONE:             return "Done";
      case TRADE_RETCODE_DONE_PARTIAL:     return "Done partial";
      case TRADE_RETCODE_ERROR:            return "Error";
      case TRADE_RETCODE_TIMEOUT:          return "Timeout";
      case TRADE_RETCODE_INVALID:          return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:   return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE:    return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS:    return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED:   return "Trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED:    return "Market closed";
      case TRADE_RETCODE_NO_MONEY:         return "No money";
      case TRADE_RETCODE_PRICE_CHANGED:    return "Price changed";
      case TRADE_RETCODE_PRICE_OFF:        return "Price off";
      case TRADE_RETCODE_INVALID_EXPIRATION:return "Invalid expiration";
      case TRADE_RETCODE_ORDER_CHANGED:    return "Order changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS:return "Too many requests";
      case TRADE_RETCODE_NO_CHANGES:       return "No changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT:return "Server disables AT";
      case TRADE_RETCODE_CLIENT_DISABLES_AT:return "Client disables AT";
      case TRADE_RETCODE_LOCKED:           return "Locked";
      case TRADE_RETCODE_FROZEN:           return "Frozen";
      case TRADE_RETCODE_INVALID_FILL:     return "Invalid fill";
      case TRADE_RETCODE_CONNECTION:       return "Connection error";
      case TRADE_RETCODE_ONLY_REAL:        return "Only real accounts";
      case TRADE_RETCODE_LIMIT_ORDERS:     return "Limit orders";
      case TRADE_RETCODE_LIMIT_VOLUME:     return "Limit volume";
      // MQL5 specific
      case TRADE_RETCODE_INVALID_ORDER:    return "Invalid order";
      case TRADE_RETCODE_POSITION_CLOSED:  return "Position closed";
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME: return "Invalid close volume";
      case TRADE_RETCODE_CLOSE_ORDER_EXIST: return "Close order exist";
      case TRADE_RETCODE_LIMIT_POSITIONS:  return "Limit positions";
      case TRADE_RETCODE_REJECT_CANCEL:    return "Reject cancel";
      case TRADE_RETCODE_LONG_ONLY:        return "Long only";
      case TRADE_RETCODE_SHORT_ONLY:       return "Short only";
      case TRADE_RETCODE_CLOSE_ONLY:       return "Close only";
      case TRADE_RETCODE_FIFO_CLOSE:       return "Fifo close";
      default:                             return "Unknown retcode " + IntegerToString(retcode);
     }
  }

// 获取Tick大小的辅助函数
double GetTickSize()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
  }
//+------------------------------------------------------------------+
