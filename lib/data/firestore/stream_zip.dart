import 'dart:async';

/// Combines a fixed number of streams into one, emitting [combine]d results.
///
/// Hand-rolled rather than pulling in `rxdart` for `ZipStream`. Three reasons:
///
///  * The shape needed here is fixed at three and four sources, so a generic
///    variadic combiner would be more machinery than the two call sites use.
///  * `rxdart` would be the only package in the dependency tree that exists for
///    this one job, and every future reader would have to check whether the
///    behaviour matched `Rx.combineLatest` or not.
///  * The exact semantics matter, and they are the whole point: **the combined
///    stream emits only once every source has emitted at least once.** That is
///    what stops the admin panel painting an empty menu for the half-second
///    between the menu query and the settings query resolving — a flash of "no
///    items" where there are nineteen, then the real list.
///
/// After that first emission it behaves like `combineLatest`: each source's next
/// value produces one combined emission.

/// Two sources.
Stream<R> zip2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) =>
    _zip<R>(<Stream<dynamic>>[a, b], (List<dynamic> v) => combine(v[0] as A, v[1] as B));

/// Three sources.
Stream<R> zip3<A, B, C, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  R Function(A a, B b, C c) combine,
) =>
    _zip<R>(<Stream<dynamic>>[a, b, c], (List<dynamic> v) => combine(v[0] as A, v[1] as B, v[2] as C));

/// Four sources.
Stream<R> zip4<A, B, C, D, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  Stream<D> d,
  R Function(A a, B b, C c, D d) combine,
) =>
    _zip<R>(<Stream<dynamic>>[a, b, c, d],
        (List<dynamic> v) => combine(v[0] as A, v[1] as B, v[2] as C, v[3] as D));

Stream<R> _zip<R>(List<Stream<dynamic>> sources, R Function(List<dynamic> latest) combine) {
  final StreamController<R> controller = StreamController<R>.broadcast();

  final List<dynamic> latest = List<dynamic>.filled(sources.length, null);
  final List<bool> seen = List<bool>.filled(sources.length, false);

  void onValue(int index, dynamic value) {
    latest[index] = value;
    seen[index] = true;

    // The gate: no emission until every source has spoken once.
    for (final bool s in seen) {
      if (!s) return;
    }
    controller.add(combine(latest));
  }

  controller.onListen = () {
    for (int i = 0; i < sources.length; i++) {
      sources[i].listen(
        (dynamic value) => onValue(i, value),
        onError: controller.addError,
      );
    }
  };

  // Closing on cancel releases the upstream subscriptions. Firestore snapshot
  // streams hold a live listener each, so leaking them keeps documents cached
  // and costs the user's data.
  controller.onCancel = () => controller.close();
  return controller.stream;
}