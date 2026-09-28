import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../stores/presentation/store_avatar.dart';
import 'order_repository.dart';

/// ============================================================================
/// THE ZATCA SIMPLIFIED TAX INVOICE (فاتورة ضريبية مبسطة)
///
/// A full, printable-looking tax document — the merchant's own logo, the seller
/// and buyer blocks, a per-line VAT breakdown, the totals, the payment line and
/// the ZATCA compliance QR. Opened on demand from the order screen ("عرض
/// الفاتورة"); shown only for a taxed order that carries an invoice.
/// ============================================================================
class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final order = ref.watch(orderProvider(orderId));

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(s.taxInvoice),
      ),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => Center(child: Text(s.error, style: const TextStyle(color: AppColors.ink500))),
        data: (data) {
          final inv = data.invoice;
          if (inv == null || inv.qr == null) {
            return Center(child: Text(s.error, style: const TextStyle(color: AppColors.ink500)));
          }
          return SingleChildScrollView(
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                child: _InvoiceBody(order: data, inv: inv, s: s),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InvoiceBody extends StatelessWidget {
  const _InvoiceBody({required this.order, required this.inv, required this.s});
  final OrderResult order;
  final OrderInvoice inv;
  final Strings s;

  String _money(double v) => v.toStringAsFixed(2);

  String _date(DateTime? dt) {
    final d = (dt ?? DateTime.now()).toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rate = inv.taxRate;
    final logo = logoUrlOf(inv.logo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(s.simplifiedTaxInvoice,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink900)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text('${s.invoiceNo}: ${inv.number ?? order.reference}   ·   ${s.invoiceDate}: ${_date(inv.issuedAt)}',
              style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
        ),
        const SizedBox(height: 16),

        // Merchant logo (their brand image), or a name chip as a fallback.
        Center(
          child: logo != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(logo, height: 72, fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _logoFallback()),
                )
              : _logoFallback(),
        ),
        const SizedBox(height: 12),

        Center(
          child: Column(
            children: [
              if ((inv.sellerName ?? '').isNotEmpty)
                Text(inv.sellerName!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
              const SizedBox(height: 4),
              if ((inv.taxNumber ?? '').isNotEmpty) _muted('${s.taxNumberLabel}: ${inv.taxNumber}'),
              if ((inv.commercialRegistration ?? '').isNotEmpty) _muted('${s.crLabel}: ${inv.commercialRegistration}'),
              if ((inv.nationalAddress ?? '').isNotEmpty) _muted('${s.addressLabel}: ${inv.nationalAddress}'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 24),

        // Buyer.
        if ((order.customerName ?? '').isNotEmpty || (order.customerPhone ?? '').isNotEmpty) ...[
          _sectionTitle(s.customerInfo),
          const SizedBox(height: 8),
          if ((order.customerName ?? '').isNotEmpty) _kv(s.fullName, order.customerName!),
          if ((order.customerPhone ?? '').isNotEmpty) _kv(s.phone, order.customerPhone!),
          const SizedBox(height: 8),
          const Divider(height: 24),
        ],

        // Products.
        _sectionTitle(s.productsInfo),
        const SizedBox(height: 10),
        _ProductsTable(order: order, rate: rate, s: s, money: _money),
        const SizedBox(height: 16),
        const Divider(height: 8),
        const SizedBox(height: 10),

        // Order totals.
        _sectionTitle(s.orderDetails),
        const SizedBox(height: 8),
        _totalRow(s.totalExclVat, _money(order.subtotal + order.deliveryFee)),
        _totalRow('${s.totalVat} ${rate.toStringAsFixed(0)}%', _money(order.taxAmount)),
        _totalRow(s.totalInclVat, _money(order.total)),
        const SizedBox(height: 8),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(s.total,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink900)),
            Text('${_money(order.total)} ${s.sar}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink900)),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 20),

        // Payment.
        _sectionTitle(s.paymentMethod),
        const SizedBox(height: 8),
        _kv(s.payOnPickup, '${_money(order.total)} ${s.sar}'),
        const SizedBox(height: 22),

        // ZATCA QR.
        Center(
          child: QrImageView(
            data: inv.qr!,
            size: 150,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Text('© ${inv.sellerName ?? ''} ${(inv.issuedAt ?? DateTime.now()).year}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.ink400)),
        ),
      ],
    );
  }

  Widget _logoFallback() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(color: AppColors.ink900, borderRadius: BorderRadius.circular(10)),
        child: Text(inv.sellerName?.characters.firstOrNull.toString() ?? '؟',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      );

  Widget _muted(String t) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
      );

  Widget _sectionTitle(String t) => Text(t,
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink900));

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
            Flexible(child: Text(v,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink900))),
          ],
        ),
      );

  Widget _totalRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(v, style: const TextStyle(fontSize: 12.5, color: AppColors.ink700)),
            Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
          ],
        ),
      );
}

/// The five-column VAT table: product · qty · taxable · VAT · incl-VAT. Delivery,
/// when charged, is its own taxable line — exactly as the reference invoice.
class _ProductsTable extends StatelessWidget {
  const _ProductsTable({required this.order, required this.rate, required this.s, required this.money});
  final OrderResult order;
  final double rate;
  final Strings s;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ink200))),
        children: [
          _h(s.productName), _h(s.qtyShort), _h(s.taxableAmount), _h(s.vat), _h(s.inclVat),
        ],
      ),
    ];

    for (final it in order.items) {
      final taxable = it.lineTotal;
      final vat = taxable * rate / 100;
      rows.add(_row(it.name, it.quantity.toString(), taxable, vat));
    }
    if (order.deliveryFee > 0) {
      final vat = order.deliveryFee * rate / 100;
      rows.add(_row(s.deliveryFeeLabel, '1', order.deliveryFee, vat));
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.8),
        3: FlexColumnWidth(1.8),
        4: FlexColumnWidth(1.8),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  TableRow _row(String name, String qty, double taxable, double vat) => TableRow(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ink100))),
        children: [
          _c(name, bold: true, align: TextAlign.right),
          _c(qty),
          _c(money(taxable)),
          _c(money(vat)),
          _c(money(taxable + vat)),
        ],
      );

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Text(t,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.ink500)),
      );

  Widget _c(String t, {bool bold = false, TextAlign align = TextAlign.center}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Text(t,
            textAlign: align,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: AppColors.ink900)),
      );
}
