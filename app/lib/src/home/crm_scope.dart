import 'package:flutter/widgets.dart';

import '../chats/chat_prefs.dart';
import '../clients/clients_repository.dart';
import '../storage/form_drafts.dart';
import '../products/product_photos.dart';
import '../products/products_repository.dart';
import '../sales/sales_repository.dart';

/// Products and sales for screens deep in the app, such as the client page
/// opened from a conversation. It sits above the navigator
/// (`MaterialApp.builder`), so every route sees it. Null while app.db is
/// closed.
class CrmScope extends InheritedWidget {
  const CrmScope({
    super.key,
    this.products,
    this.sales,
    this.clients,
    this.photos,
    this.chatPrefs,
    this.drafts,
    required super.child,
  });

  final ProductsRepository? products;
  final SalesRepository? sales;

  /// For a sale started outside Vendas, such as from a product's page
  final ClientsRepository? clients;
  final PhotoPicker? photos;

  /// Quick replies and ignored contacts.
  final ChatPrefs? chatPrefs;

  /// What new forms keep while typed.
  final FormDrafts? drafts;

  static CrmScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CrmScope>();

  @override
  bool updateShouldNotify(CrmScope old) =>
      products != old.products ||
      sales != old.sales ||
      clients != old.clients ||
      photos != old.photos ||
      chatPrefs != old.chatPrefs ||
      drafts != old.drafts;
}
