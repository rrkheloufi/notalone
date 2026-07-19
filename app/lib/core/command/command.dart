import 'package:flutter/foundation.dart';
import 'package:notalone/core/result/result.dart';

typedef CommandAction0<T> = Future<Result<T>> Function();

/// Pattern Command du guide d'architecture officiel Flutter : encapsule une
/// action de ViewModel et rend son état (en cours / succès / échec)
/// observable par la vue. Ignore les exécutions concurrentes.
sealed class Command<T> extends ChangeNotifier {
  bool _running = false;
  bool get running => _running;

  Result<T>? _result;
  Result<T>? get result => _result;

  bool get error => _result is Err<T>;
  bool get completed => _result is Ok<T>;

  void clearResult() {
    _result = null;
    notifyListeners();
  }

  Future<void> _execute(CommandAction0<T> action) async {
    if (_running) return;
    _running = true;
    _result = null;
    notifyListeners();
    try {
      _result = await action();
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

final class Command0<T> extends Command<T> {
  Command0(this._action);

  final CommandAction0<T> _action;

  Future<void> execute() => _execute(_action);
}

typedef CommandAction1<T, A> = Future<Result<T>> Function(A argument);

final class Command1<T, A> extends Command<T> {
  Command1(this._action);

  final CommandAction1<T, A> _action;

  Future<void> execute(A argument) => _execute(() => _action(argument));
}
