import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/todo.dart';
import 'calendar_view.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'todo_edit_screen.dart';
import 'todo_list_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  Future<void> _newTodo() async {
    final todo = await Navigator.of(context).push<Todo>(
      MaterialPageRoute(builder: (_) => const TodoEditScreen()),
    );
    if (todo != null) await widget.state.saveTodo(todo);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_tab == 0 ? 'ToDos' : 'Kalender'),
          actions: [
            _SyncStatusButton(state: state),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'settings') {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettingsScreen(state: state)));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'settings', child: Text('Einstellungen')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (state.syncError != null)
              MaterialBanner(
                content: Text(state.syncError!),
                leading: const Icon(Icons.cloud_off, color: Colors.red),
                actions: [
                  TextButton(
                    onPressed: () => state.syncNow(),
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  TodoListView(state: state),
                  CalendarView(state: state),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _newTodo,
          tooltip: 'Neues ToDo',
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.checklist), label: 'Liste'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month), label: 'Kalender'),
          ],
        ),
      ),
    );
  }
}

/// Sync-Status in der AppBar: Spinner, Fehler, ausstehende Änderungen.
class _SyncStatusButton extends StatelessWidget {
  const _SyncStatusButton({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final String tooltip;
    if (state.syncing) {
      tooltip = 'Synchronisiert …';
    } else if (state.syncError != null) {
      tooltip = state.syncError!;
    } else if (state.lastSync != null) {
      tooltip = 'Letzter Sync: ${formatDateTime(state.lastSync!)}'
          '${state.pendingCount > 0 ? ' — ${state.pendingCount} ausstehend' : ''}';
    } else {
      tooltip = 'Noch nicht synchronisiert';
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: state.syncing ? null : () => state.syncNow(),
      icon: state.syncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Badge(
              isLabelVisible: state.pendingCount > 0,
              label: Text('${state.pendingCount}'),
              child: Icon(
                state.syncError != null ? Icons.cloud_off : Icons.cloud_done,
                color: state.syncError != null ? Colors.red : null,
              ),
            ),
    );
  }
}
