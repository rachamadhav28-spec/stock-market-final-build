import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const PennyTraderApp());
}

class PennyTraderApp extends StatelessWidget {
  const PennyTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Penny Stock Trader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Stage1Screen(),
    );
  }
}

class StockItem {
  final String symbol;
  final String name;
  double price;
  DateTime? lastTradeTime;
  bool isDelayed;
  bool isLoading;
  String errorMessage;

  StockItem({
    required this.symbol,
    required this.name,
    this.price = 0.0,
    this.lastTradeTime,
    this.isDelayed = false,
    this.isLoading = true,
    this.errorMessage = '',
  });
}

class Stage1Screen extends StatefulWidget {
  const Stage1Screen({super.key});

  @override
  State<Stage1Screen> createState() => _Stage1ScreenState();
}

class _Stage1ScreenState extends State<Stage1Screen> {
  final List<StockItem> _stocks = [
    StockItem(symbol: 'IDEA.NS', name: 'Vodafone Idea Ltd'),
    StockItem(symbol: 'YESBANK.NS', name: 'Yes Bank Ltd'),
    StockItem(symbol: 'JPPOWER.NS', name: 'Jaiprakash Power Ventures'),
    StockItem(symbol: 'RPOWER.NS', name: 'Reliance Power Ltd'),
    StockItem(symbol: 'GTLINFRA.NS', name: 'GTL Infrastructure Ltd'),
  ];

  int _selectedIndex = 0;
  bool _isMarketOpen = false;

  @override
  void initState() {
    super.initState();
    _checkMarketHoursAndFetch();
  }

  bool _checkMarketHoursNow() {
    // Check if IST time is Monday-Friday between 9:15 AM and 3:30 PM
    final nowUtc = DateTime.now().toUtc();
    final nowIst = nowUtc.add(const Duration(hours: 5, minutes: 30));
    final weekday = nowIst.weekday; // 1 = Mon, 7 = Sun

    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return false;
    }

    final timeMinutes = nowIst.hour * 60 + nowIst.minute;
    const marketOpen = 9 * 60 + 15; // 9:15 AM
    const marketClose = 15 * 60 + 30; // 3:30 PM

    return timeMinutes >= marketOpen && timeMinutes <= marketClose;
  }

  Future<void> _checkMarketHoursAndFetch() async {
    setState(() {
      _isMarketOpen = _checkMarketHoursNow();
    });

    // Fetch prices for all stocks
    for (var stock in _stocks) {
      await _fetchStockData(stock);
    }
  }

  Future<void> _fetchStockData(StockItem stock) async {
    setState(() {
      stock.isLoading = true;
      stock.errorMessage = '';
    });

    try {
      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/${stock.symbol}?interval=1m&range=1d');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['chart']['result'][0];
        final meta = result['meta'];
        
        final double currentPrice = (meta['regularMarketPrice'] ?? 0.0).toDouble();
        final int timestampSec = meta['regularMarketTime'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
        
        final tradeTime = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000, isUtc: true)
            .add(const Duration(hours: 5, minutes: 30)); // Convert to IST

        final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
        final differenceMinutes = nowIst.difference(tradeTime).inMinutes;

        setState(() {
          stock.price = currentPrice;
          stock.lastTradeTime = tradeTime;
          stock.isDelayed = differenceMinutes > 5;
          stock.isLoading = false;
        });
      } else {
        setState(() {
          stock.errorMessage = 'HTTP Error: ${response.statusCode}';
          stock.isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        stock.errorMessage = 'Connection failed';
        stock.isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedStock = _stocks[_selectedIndex];
    final formatter = DateFormat('hh:mm:ss a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Penny Trader - Stage 1'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkMarketHoursAndFetch,
            tooltip: 'Refresh Prices',
          )
        ],
      ),
      body: Column(
        children: [
          // Market Status Banner
          Container(
            padding: const EdgeInsets.all(12),
            color: _isMarketOpen ? Colors.green.shade100 : Colors.red.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isMarketOpen ? Icons.fiber_manual_record : Icons.pause_circle,
                  color: _isMarketOpen ? Colors.green.shade800 : Colors.red.shade800,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isMarketOpen ? 'NSE Market OPEN (Live Polling Active)' : 'Market CLOSED (Showing Last Snapshot)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isMarketOpen ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
              ],
            ),
          ),
          
          // Stock Selector Tabs
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _stocks.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: ChoiceChip(
                    label: Text(_stocks[index].symbol.replaceAll('.NS', '')),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Selected Stock Details Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedStock.symbol,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          if (selectedStock.isDelayed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PRACTICE ONLY - DELAYED DATA',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        selectedStock.name,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      if (selectedStock.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (selectedStock.errorMessage.isNotEmpty)
                        Center(
                          child: Text(
                            selectedStock.errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      else ...[
                        const Text('Current Price (INR)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        Text(
                          'Rs ${selectedStock.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              'Last Trade Time (IST): ${selectedStock.lastTradeTime != null ? formatter.format(selectedStock.lastTradeTime!) : "N/A"}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                      const Spacer(),
                      const Divider(),
                      const Text(
                        'Google Finance Verification Test:\nOpen google.com/finance/quote/${selectedStock.symbol.replaceAll(".NS", ":NSE")} in your browser during market hours to compare this price.',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
