import 'package:flutter/material.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'package:dayday_usta/services/category_metrics_service.dart';

/// Подпись очереди поиска: `searchMeta` + среднее время accept по категории.
///
/// [Future] для метрики создаётся один раз на [order.category] и обновляется
/// только при смене категории — не при каждом перестроении родителя.
class PendingClientSearchSubtitle extends StatefulWidget {
  final app_order.Order order;
  final TextStyle? style;

  const PendingClientSearchSubtitle({
    super.key,
    required this.order,
    this.style,
  });

  @override
  State<PendingClientSearchSubtitle> createState() =>
      _PendingClientSearchSubtitleState();
}

class _PendingClientSearchSubtitleState
    extends State<PendingClientSearchSubtitle> {
  final CategoryMetricsService _metrics = CategoryMetricsService();
  late Future<double?> _avgFuture;

  @override
  void initState() {
    super.initState();
    _avgFuture = _metrics.getAvgFirstAcceptSeconds(widget.order.category);
  }

  @override
  void didUpdateWidget(PendingClientSearchSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.category != widget.order.category) {
      _avgFuture = _metrics.getAvgFirstAcceptSeconds(widget.order.category);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.order.searchMeta ??
        app_order.OrderSearchMeta(
          mastersFound: 0,
          notifiedCount: 0,
          radiusWaveKm: null,
        );
    return FutureBuilder<double?>(
      future: _avgFuture,
      builder: (context, snap) {
        return Text(
          meta.pendingSearchLinesAz(
            widget.order.type,
            avgFirstAcceptSeconds: snap.data,
          ),
          textAlign: TextAlign.center,
          style: widget.style,
        );
      },
    );
  }
}
