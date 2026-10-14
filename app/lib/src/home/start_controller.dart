import 'package:flutter/foundation.dart';

import '../chats/chat_clients.dart' show findChatClient;
import '../chats/chat_filters.dart';
import '../clients/clients_controller.dart' show daysUntilBirthday;
import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../products/pricing.dart' show isoDay;
import '../products/products_repository.dart';
import '../sales/sales_repository.dart';

/// An installment left to receive, due today or overdue.
typedef Receivable = ({Sale sale, int number, String due, int left});

/// A client whose birthday is within the week.
typedef Birthday = ({Client client, int inDays});

/// A product sold in the month: its description and the quantity
/// (thousandths) and amount sold.
typedef TopProduct = ({String name, int quantity, int amount});

/// A product needing attention: expired or expiring, out
/// of stock or low, in one row.
typedef ProductAlert = ({Product product, bool expiry, bool stock});

/// The numbers of one month.
typedef MonthNumbers = ({
  int revenue,
  int count,
  int profit,
  List<TopProduct> top,
});

/// The Início: what to do today and the month's numbers,
/// computed in memory from the encrypted app.db.
class StartController extends ChangeNotifier {
  StartController({
    required this.clients,
    required this.products,
    required this.sales,
    this.bridge,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ClientsRepository? clients;
  final ProductsRepository? products;
  final SalesRepository? sales;

  /// The conversations, for "Conversas sem resposta".
  final CoreBridge? bridge;
  final DateTime Function() _clock;

  /// The chats waiting for a reply, the ones waiting longest first.
  List<ChatSummary> waiting = const [];

  /// The clients of the first [waitingShown] waiting chats.
  Map<String, Client> waitingClients = const {};
  static const waitingShown = 3;

  bool loaded = false;
  List<Receivable> receivables = const [];
  List<Birthday> birthdays = const [];
  List<Product> lowStock = const [];

  /// Active products expired or expiring within 30 days, the soonest
  /// first.
  List<Product> expiring = const [];
  List<Sale> _sales = const [];
  bool _hasData = false;

  /// The month shown in the numbers.
  late DateTime month = DateTime(_clock().year, _clock().month);

  DateTime get today => _clock();

  /// Each product of [lowStock] and [expiring] once, the most urgent
  /// first: expired, out of stock, expiring soonest, low.
  List<ProductAlert> get productAlerts {
    final now = _clock();
    final byId = <int?, ProductAlert>{
      for (final p in expiring) p.id: (product: p, expiry: true, stock: false),
    };
    for (final p in lowStock) {
      byId[p.id] = (
        product: p,
        expiry: byId[p.id]?.expiry ?? false,
        stock: true,
      );
    }
    int rank(ProductAlert a) => a.expiry && a.product.expiresIn(now)! < 0
        ? 0
        : a.stock && a.product.outOfStock
        ? 1
        : a.expiry
        ? 2
        : 3;
    return byId.values.toList()..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byDays = (a.product.expiresIn(now) ?? 1 << 30).compareTo(
        b.product.expiresIn(now) ?? 1 << 30,
      );
      return byDays != 0 ? byDays : a.product.stock.compareTo(b.product.stock);
    });
  }

  /// Nothing registered yet: the Início shows the first step.
  bool get firstRun => loaded && !_hasData;

  /// What is due today and overdue, in total.
  int get receivableTotal => receivables.fold(0, (sum, r) => sum + r.left);

  Future<void> load() async {
    final now = _clock();
    final todayIso = isoDay(now);
    final allClients = await clients?.list() ?? const <Client>[];
    final allProducts = await products?.list() ?? const <Product>[];
    _sales = await sales?.list() ?? const <Sale>[];
    await _loadWaiting(now);
    _hasData =
        allClients.isNotEmpty ||
        allProducts.isNotEmpty ||
        _sales.isNotEmpty ||
        waiting.isNotEmpty;

    final due = <Receivable>[];
    for (final s in _sales) {
      if (s.canceled || s.open == 0) continue;
      final paid = s.installmentPaid;
      for (final (i, inst) in s.installments.indexed) {
        final left = inst.amount - paid[i];
        if (left > 0 && inst.due.compareTo(todayIso) <= 0) {
          due.add((sale: s, number: inst.number, due: inst.due, left: left));
        }
      }
    }
    due.sort((a, b) => a.due.compareTo(b.due)); // the oldest first
    receivables = due;

    birthdays = [
      for (final c in allClients)
        if (daysUntilBirthday(c.birthday, now) case final d? when d <= 7)
          (client: c, inDays: d),
    ]..sort((a, b) => a.inDays.compareTo(b.inDays));

    lowStock = [
      for (final p in allProducts)
        if (p.active && (p.outOfStock || p.lowStock)) p,
    ]..sort((a, b) => a.stock.compareTo(b.stock));

    expiring = [
      for (final p in allProducts)
        if (p.expiringSoon(now)) p,
    ]..sort((a, b) => a.expiresIn(now)!.compareTo(b.expiresIn(now)!));

    loaded = true;
    notifyListeners();
  }

  /// Only the conversations part, when a message arrives.
  Future<void> reloadWaiting() async {
    await _loadWaiting(_clock());
    if (waiting.isNotEmpty) _hasData = true;
    notifyListeners();
  }

  Future<void> _loadWaiting(DateTime now) async {
    final b = bridge;
    if (b == null) return;
    List<ChatSummary> chats;
    try {
      chats = b.listChats();
    } on CoreException {
      chats = const []; // WhatsApp not started
    }
    final list = waitingChats(chats, now);
    final found = <String, Client>{};
    if (clients case final repo?) {
      for (final c in list.take(waitingShown)) {
        if (await findChatClient(repo, b, c.jid) case final client?) {
          found[c.jid] = client;
        }
      }
    }
    waiting = list;
    waitingClients = found;
  }

  /// Shows the previous or the next month.
  void moveMonth(int by) {
    month = DateTime(month.year, month.month + by);
    notifyListeners();
  }

  /// Whether the next month would be in the future.
  bool get atCurrentMonth {
    final now = _clock();
    return month.year == now.year && month.month == now.month;
  }

  /// The numbers of [month]: sales made in it, not cancelled.
  MonthNumbers get numbers {
    var revenue = 0, count = 0, profit = 0;
    final byName = <String, ({int quantity, int amount})>{};
    for (final s in _sales) {
      if (s.canceled ||
          s.soldAt.year != month.year ||
          s.soldAt.month != month.month) {
        continue;
      }
      revenue += s.total;
      profit += s.profit;
      count++;
      for (final i in s.items) {
        final was = byName[i.description] ?? (quantity: 0, amount: 0);
        byName[i.description] = (
          quantity: was.quantity + i.quantity,
          amount: was.amount + i.total,
        );
      }
    }
    final top = [
      for (final e in byName.entries)
        (name: e.key, quantity: e.value.quantity, amount: e.value.amount),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return (
      revenue: revenue,
      count: count,
      profit: profit,
      top: top.take(5).toList(),
    );
  }
}
