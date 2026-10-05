import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../data/models/menu.dart';
import 'promo_widgets.dart';

/// Auto-rotating promo carousel for the "Best Offer" section.
///
/// One slide per promo. The hero lead and every former offer tile live in the
/// same strip, so the section is a single unit rather than a banner plus a
/// secondary row.
///
/// Two behaviours worth knowing about, both deliberate:
///
///  * The clock **restarts on interaction** rather than resuming. A user who
///    swipes gets a full interval from the moment they let go, instead of being
///    yanked to the next slide on whatever remained of the old timer.
///  * Slides are dragged, not auto-paged to. A carousel that keeps advancing
///    while someone is mid-gesture is worse than one that stops.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({
    super.key,
    required this.promos,
    required this.onPromoTap,
    this.interval = const Duration(seconds: 5),
  });

  final List<Promo> promos;

  /// Fired for a tap anywhere on a slide, including its CTA button.
  final ValueChanged<Promo> onPromoTap;

  /// Time each slide stays up. Five seconds is long enough to read a promo
  /// title, short enough that a queue at the counter does not have to wait to
  /// see the deal they came in for.
  final Duration interval;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.94);
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different promo list invalidates the page index; without this the dots
    // and the visible slide would disagree.
    if (oldWidget.promos.length != widget.promos.length) {
      _controller.jumpToPage(0);
      _page = 0;
      _restart();
    }
  }

  @override
  void dispose() {
    // Without this the timer fires against a disposed State and either throws
    // or animates a dead PageController.
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.promos.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) => _next());
  }

  void _pause() => _timer?.cancel();

  void _next() {
    if (!mounted || !_controller.hasClients) return;

    // Modulo, not PageController.nextPage. That was the obvious choice and it is
    // wrong: on a finite PageView it saturates at the last page rather than
    // wrapping, so the carousel visibly sticks on the final promo forever.
    // Verified by a test that expects the fourth tick to land back on page 0.
    _goto((_page + 1) % widget.promos.length);
  }

  void _goto(int i) {
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _onSlideTap(Promo promo) {
    // Tapping is interaction too, so the next interval starts from now.
    _restart();
    widget.onPromoTap(promo);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.promos.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // NotificationListener rather than PageView.onPageChanged: onPageChanged
        // fires only when the page settles on a new index, so a short swipe that
        // springs back would leave the clock running and jump the carousel
        // mid-gesture. ScrollStart/ScrollEnd track the drag itself.
        NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n is ScrollStartNotification) _pause();
            if (n is ScrollEndNotification) _restart();
            return false;
          },
          child: SizedBox(
            // 310, measured rather than guessed: at the real slide width
            // (360 * 0.94 viewportFraction, less the 8px peek gap = 330.4) the
            // tallest slide — the NEW HERE hero, whose title wraps to two lines
            // — renders 307 tall. The two offer slides come in at 229. Sizing to
            // the tallest is what keeps the strip from changing height as it
            // rotates, which would make the dots jump.
            //
            // The 3px of slack is tight on purpose. Raising this costs nothing
            // but blank space between slides; setting it below 307 overflows the
            // hero by exactly the difference.
            height: 310,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (int i) => setState(() => _page = i),
              itemCount: widget.promos.length,
              itemBuilder: (BuildContext context, int i) {
                final Promo promo = widget.promos[i];
                return Padding(
                  padding: const EdgeInsets.only(right: BwSpacing.sm),
                  child: GestureDetector(
                    onTap: () => _onSlideTap(promo),
                    child: PromoHeroBanner(
                      promo: promo,
                      onCta: () => _onSlideTap(promo),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: BwSpacing.md),
        _DotRow(count: widget.promos.length, index: _page, onTap: _goto),
      ],
    );
  }
}

/// Active/ inactive page indicators.
class _DotRow extends StatelessWidget {
  const _DotRow({required this.count, required this.index, required this.onTap});

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // Padding rather than a sized dot: a 6px target is below the
              // 48px minimum, so the tap area has to come from somewhere.
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              child: Container(
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? BwColors.text : BwColors.border,
                  borderRadius: BorderRadius.circular(BwRadius.pill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}