import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ============ EASY CUSTOMIZATION ============
const Color kGreen = Color(0xFF00B386);
const Color kRed = Color(0xFFEB5B3C);
const Color kAmber = Color(0xFFF5A623);
const Color kBg = Color(0xFFF4F5F7);
const Color kText = Color(0xFF1B1D21);
const Color kMuted = Color(0xFF7C7E8C);

const double kCapital = 10000; // paper money (Rs)
const double kMaxLoss = 100; // max loss per trade (Rs)
const int kRefreshSeconds = 15;

const List<List<String>> kWatchlist = [
  ['IDEA.NS', 'Vodafone Idea'],
  ['YESBANK.NS', 'Yes Bank'],
  ['JPPOWER.NS', 'Jaiprakash Power'],
  ['RPOWER.NS', 'Reliance Power'],
  ['GTLINFRA.NS', 'GTL Infrastructure'],
];
// ============================================

void main() {
  runApp(const PennyTraderApp());
}

class PennyTraderApp extends StatelessWidget {
  const PennyTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Penny Trader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
        fontFamily: 'Roboto',
      ),
      home: const HomePage(),
    );
  }
}

// ---------------- Data ----------------

class Stock {
  final String symbol;
  final String name;
  double price = 0;
  double prevClose = 0;
  DateTime? tradeTime; // IST
  List<double> closes = [];
  bool loading = true;
  String error = '';

  Stock(this.symbol, this.name);

  String get shortName => symbol.replaceAll('.NS', '');
  double get change => prevClose == 0 ? 0 : price - prevClose;
  double get changePct => prevClose == 0 ? 0 : change / prevClose * 100;
  bool get up => change >= 0;

  bool get delayed {
    final t = tradeTime;
    if (t == null) return false;
    return istNow().difference(t).inMinutes > 5;
  }
}

DateTime istNow() =>
    DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

bool isMarketOpen() {
  final n = istNow();
  if (n.weekday == DateTime.saturday || n.weekday == DateTime.sunday) {
    return false;
  }
  final m = n.hour * 60 + n.minute;
  return m >= 9 * 60 + 15 && m <= 15 * 60 + 30;
}

class Signal {
  final String action; // BUY / SELL / WAIT
  final double entry;
  final double stop;
  final double target;
  final int shares;
  final double maxLoss;
  const Signal(this.action, this.entry, this.stop, this.target, this.shares,
      this.maxLoss);
}

// Simple practice rule (not advice): price vs recent average + momentum.
Signal makeSignal(Stock s) {
  final c = s.closes;
  if (c.length < 10 || s.price <= 0) {
    return const Signal('WAIT', 0, 0, 0, 0, 0);
  }
  final recent = c.length > 20 ? c.sublist(c.length - 20) : c;
  final avg = recent.reduce((a, b) => a + b) / recent.length;
  final last = c.last;
  final momentum = last - c[c.length - 6];

  String action = 'WAIT';
  if (last > avg && momentum > 0) action = 'BUY';
  if (last < avg && momentum < 0) action = 'SELL';
  if (action == 'WAIT') return Signal('WAIT', last, 0, 0, 0, 0);

  final risk = last * 0.01; // 1% stop
  final stop = action == 'BUY' ? last - risk : last + risk;
  final target = action == 'BUY' ? last + 2 * risk : last - 2 * risk;
  int shares = (kMaxLoss / risk).floor();
  final cap = (kCapital / last).floor();
  if (shares > cap) shares = cap;
  return Signal(action, last, stop, target, shares, shares * risk);
}

class Store extends ChangeNotifier {
  final List<Stock> stocks =
      kWatchlist.map((e) => Stock(e[0], e[1])).toList();
  Timer? _timer;

  void start() {
    refreshAll();
    _timer = Timer.periodic(const Duration(seconds: kRefreshSeconds), (_) {
      if (isMarketOpen()) refreshAll();
    });
  }

  Future<void> refreshAll() async {
    await Future.wait(stocks.map(fetch));
  }

  Future<void> fetch(Stock s) async {
    try {
      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/${s.symbol}?interval=5m&range=1d');
      final res = await http
          .get(url, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        s.error = 'Server error ${res.statusCode}';
      } else {
        final data = jsonDecode(res.body);
        final result = data['chart']['result'][0];
        final meta = result['meta'];
        s.price = (meta['regularMarketPrice'] as num).toDouble();
        final prev = meta['chartPreviousClose'] ?? meta['previousClose'] ?? 0;
        s.prevClose = (prev as num).toDouble();
        final ts = (meta['regularMarketTime'] as num).toInt();
        s.tradeTime = DateTime.fromMillisecondsSinceEpoch(ts * 1000,
                isUtc: true)
            .add(const Duration(hours: 5, minutes: 30));
        final raw = result['indicators']['quote'][0]['close'] as List;
        s.closes = raw
            .where((v) => v != null)
            .map<double>((v) => (v as num).toDouble())
            .toList();
        s.error = '';
      }
    } catch (_) {
      s.error = 'No connection';
    }
    s.loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ---------------- Home: stock list ----------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Store store = Store();

  @override
  void initState() {
    super.initState();
    store.start();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = isMarketOpen();
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            return RefreshIndicator(
              onRefresh: store.refreshAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Stocks',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: kText)),
                      ),
                      Pill(
                        text: open ? 'Market open' : 'Market closed',
                        color: open ? kGreen : kMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final s in store.stocks)
                    StockCard(
                      stock: s,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => DetailPage(store: store, stock: s)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text('Practice only. Not financial advice.',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class StockCard extends StatelessWidget {
  final Stock stock;
  final VoidCallback onTap;
  const StockCard({super.key, required this.stock, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = stock.up ? kGreen : kRed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stock.shortName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kText)),
                      const SizedBox(height: 4),
                      Text(stock.name,
                          style: const TextStyle(color: kMuted, fontSize: 13)),
                    ],
                  ),
                ),
                if (stock.loading)
                  const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (stock.error.isNotEmpty && stock.price == 0)
                  Text(stock.error,
                      style: const TextStyle(color: kRed, fontSize: 12))
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Rs ${stock.price.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: color)),
                      const SizedBox(height: 4),
                      Text(
                          '${stock.up ? '+' : ''}${stock.change.toStringAsFixed(2)} (${stock.changePct.toStringAsFixed(2)}%)',
                          style: TextStyle(color: color, fontSize: 13)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Detail ----------------

class DetailPage extends StatelessWidget {
  final Store store;
  final Stock stock;
  const DetailPage({super.key, required this.store, required this.stock});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: kText,
        title: Text(stock.shortName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final color = stock.up ? kGreen : kRed;
          final sig = makeSignal(stock);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              BigBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rs ${stock.price.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    const SizedBox(height: 4),
                    Text(
                        '${stock.up ? '+' : ''}${stock.change.toStringAsFixed(2)} (${stock.changePct.toStringAsFixed(2)}%) today',
                        style: TextStyle(color: color, fontSize: 14)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: CustomPaint(
                          painter: LinePainter(stock.closes, color)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (!isMarketOpen())
                          const Pill(text: 'Market closed', color: kMuted),
                        if (stock.delayed)
                          const Pill(text: 'Delayed data', color: kAmber),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SignalBox(sig: sig),
              const SizedBox(height: 12),
              if (sig.action != 'WAIT')
                Row(
                  children: [
                    Expanded(
                        child: NumBox(
                            label: 'Entry',
                            value: sig.entry.toStringAsFixed(2),
                            color: kText)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: NumBox(
                            label: 'Stop-loss',
                            value: sig.stop.toStringAsFixed(2),
                            color: kRed)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: NumBox(
                            label: 'Target',
                            value: sig.target.toStringAsFixed(2),
                            color: kGreen)),
                  ],
                ),
              if (sig.action != 'WAIT') const SizedBox(height: 12),
              if (sig.action != 'WAIT')
                BigBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${sig.shares} shares',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('Max loss Rs ${sig.maxLoss.toStringAsFixed(0)}',
                          style: const TextStyle(color: kRed, fontSize: 14)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const Center(
                child: Text('Practice signal. Paper trading only.',
                    style: TextStyle(color: kMuted, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SignalBox extends StatelessWidget {
  final Signal sig;
  const SignalBox({super.key, required this.sig});

  @override
  Widget build(BuildContext context) {
    final Color c = sig.action == 'BUY'
        ? kGreen
        : sig.action == 'SELL'
            ? kRed
            : kAmber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Text('SIGNAL',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sig.action,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class NumBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const NumBox(
      {super.key,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class BigBox extends StatelessWidget {
  final Widget child;
  const BigBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: child,
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class LinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  LinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - (data[i] - minV) / range * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant LinePainter old) =>
      old.data != data || old.color != color;
}
