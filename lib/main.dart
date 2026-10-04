import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final DateFormat _df = DateFormat('yyyy-MM-dd');
String fmtDate(DateTime d) => _df.format(d);
String todayStr() => fmtDate(DateTime.now());
String fmtNum(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

class Habit {
  final int? id;
  final String name;
  final String unit;
  final double? target;
  final bool remindEnabled;
  final int remindHour;
  final int remindMinute;
  final int colorValue;
  final int sortOrder;
  final int createdAt;

  Habit({
    this.id,
    required this.name,
    this.unit = '',
    this.target,
    this.remindEnabled = false,
    this.remindHour = 21,
    this.remindMinute = 0,
    this.colorValue = 0xFF4CAF50,
    this.sortOrder = 0,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'unit': unit,
        'target': target,
        'remindEnabled': remindEnabled ? 1 : 0,
        'remindHour': remindHour,
        'remindMinute': remindMinute,
        'colorValue': colorValue,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
      };

  factory Habit.fromMap(Map<String, Object?> m) => Habit(
        id: m['id'] as int?,
        name: m['name'] as String,
        unit: (m['unit'] as String?) ?? '',
        target: (m['target'] as num?)?.toDouble(),
        remindEnabled: (m['remindEnabled'] as int? ?? 0) == 1,
        remindHour: m['remindHour'] as int? ?? 21,
        remindMinute: m['remindMinute'] as int? ?? 0,
        colorValue: m['colorValue'] as int? ?? 0xFF4CAF50,
        sortOrder: m['sortOrder'] as int? ?? 0,
        createdAt: m['createdAt'] as int? ?? 0,
      );
}

class DB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final p = '$dbPath/habit_tracker.db';
    _db = await openDatabase(p, version: 1, onCreate: (d, v) async {
      await d.execute('''CREATE TABLE habits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT '',
        target REAL,
        remindEnabled INTEGER NOT NULL DEFAULT 0,
        remindHour INTEGER NOT NULL DEFAULT 21,
        remindMinute INTEGER NOT NULL DEFAULT 0,
        colorValue INTEGER NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL)''');
      await d.execute('''CREATE TABLE check_ins(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        habitId INTEGER NOT NULL,
        date TEXT NOT NULL,
        value REAL NOT NULL,
        updatedAt INTEGER NOT NULL,
        UNIQUE(habitId, date))''');
      await d.execute('''CREATE TABLE memos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        content TEXT NOT NULL,
        updatedAt INTEGER NOT NULL)''');
    });
    return _db!;
  }

  static Future<List<Habit>> habits() async {
    final d = await db;
    final rows = await d.query('habits', orderBy: 'sortOrder ASC, id ASC');
    return rows.map(Habit.fromMap).toList();
  }

  static Future<int> insertHabit(Habit h) async =>
      (await db).insert('habits', h.toMap());

  static Future<void> updateHabit(Habit h) async =>
      (await db).update('habits', h.toMap(), where: 'id = ?', whereArgs: [h.id]);

  static Future<void> deleteHabit(int id) async {
    final d = await db;
    await d.delete('habits', where: 'id = ?', whereArgs: [id]);
    await d.delete('check_ins', where: 'habitId = ?', whereArgs: [id]);
  }

  static Future<Map<int, double>> valuesOf(String date) async {
    final d = await db;
    final rows = await d.query('check_ins', where: 'date = ?', whereArgs: [date]);
    return {
      for (final r in rows) r['habitId'] as int: (r['value'] as num).toDouble()
    };
  }

  static Future<void> setValue(int habitId, String date, double? v) async {
    final d = await db;
    if (v == null) {
      await d.delete('check_ins',
          where: 'habitId = ? AND date = ?', whereArgs: [habitId, date]);
    } else {
      await d.insert(
          'check_ins',
          {
            'habitId': habitId,
            'date': date,
            'value': v,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<Map<String, int>> monthCounts(String ym) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT date, COUNT(*) c FROM check_ins WHERE date LIKE ? GROUP BY date',
        ['$ym%']);
    return {for (final r in rows) r['date'] as String: r['c'] as int};
  }

  static Future<List<Map<String, Object?>>> memosOf(String date) async {
    final d = await db;
    return d.query('memos',
        where: 'date = ?', whereArgs: [date], orderBy: 'id DESC');
  }

  static Future<Set<String>> memoDates(String ym) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT DISTINCT date FROM memos WHERE date LIKE ?', ['$ym%']);
    return rows.map((r) => r['date'] as String).toSet();
  }

  static Future<int> addMemo(String date, String content) async =>
      (await db).insert('memos', {
        'date': date,
        'content': content,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

  static Future<void> updateMemo(int id, String content) async =>
      (await db).update('memos',
          {'content': content, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteMemo(int id) async =>
      (await db).delete('memos', where: 'id = ?', whereArgs: [id]);

  static Future<List<Map<String, Object?>>> rangeValues(int habitId, int days) async {
    final d = await db;
    final now = DateTime.now();
    final from = fmtDate(now.subtract(Duration(days: days - 1)));
    final to = fmtDate(now);
    return d.query('check_ins',
        where: 'habitId = ? AND date >= ? AND date <= ?',
        whereArgs: [habitId, from, to],
        orderBy: 'date ASC');
  }

  static Future<List<Map<String, Object?>>> allValues(int habitId) async {
    final d = await db;
    return d.query('check_ins',
        where: 'habitId = ?', whereArgs: [habitId], orderBy: 'date ASC');
  }
}
class Notif {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final n = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(n));
    } catch (_) {}
    await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    final impl = _p.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
    await impl?.requestExactAlarmsPermission();
    _ready = true;
  }

  static Future<void> schedule(Habit h) async {
    await init();
    await _p.cancel(h.id!);
    if (!h.remindEnabled) return;
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, h.remindHour, h.remindMinute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _p.zonedSchedule(
  h.id!,
  '打卡提醒：${h.name}',
  h.target == null
      ? '别忘了打卡哦'
      : '目标 ${fmtNum(h.target)}${h.unit}，加油！',
  next,
  const NotificationDetails(
    android: AndroidNotificationDetails(
      'habit_daily', '打卡提醒',
      channelDescription: '每日打卡提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
  ),
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  matchDateTimeComponents: DateTimeComponents.time,
  uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime, // 👈 就是加了这半行
);
  }

  static Future<void> cancel(int id) async => _p.cancel(id);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notif.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '打卡',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF4CAF50)),
        home: const RootPage(),
      );
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _idx = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _idx,
          children: const [TodayPage(), CalendarPage()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _idx,
          onDestinationSelected: (i) => setState(() => _idx = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.check_circle_outline), label: '今日'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month), label: '日历'),
          ],
        ),
      );
}

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  List<Habit> _habits = [];
  Map<int, double> _values = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final hs = await DB.habits();
    final vs = await DB.valuesOf(todayStr());
    setState(() {
      _habits = hs;
      _values = vs;
      _loading = false;
    });
  }

  Future<void> _editValue(Habit h) async {
    final cur = _values[h.id!];
    final ctrl = TextEditingController(text: fmtNum(cur));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(h.name),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入今天完成的数值',
            suffixText: h.unit.isEmpty ? null : h.unit,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, '__clear__'),
              child: const Text('清除')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (r == null) return;
    if (r == '__clear__') {
      await DB.setValue(h.id!, todayStr(), null);
    } else {
      final v = double.tryParse(r.trim());
      if (v == null) return;
      await DB.setValue(h.id!, todayStr(), v);
    }
    await _load();
  }

  Future<void> _openEditor([Habit? h]) async {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => EditHabitPage(habit: h)));
    if (saved == true) await _load();
  }

  Future<void> _openChart(Habit h) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ChartPage(habit: h)));
  }

  Future<void> _confirmDelete(Habit h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${h.name}」？'),
        content: const Text('所有打卡记录也会一起删除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DB.deleteHabit(h.id!);
      await Notif.cancel(h.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('今日 · ${todayStr()}'),
          actions: [
            IconButton(
                onPressed: () => _openEditor(), icon: const Icon(Icons.add)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _habits.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 140),
                        Center(child: Text('还没有打卡项\n点右上角 + 新建一个',
                            textAlign: TextAlign.center)),
                      ])
                    : ListView.separated(
                        itemCount: _habits.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final h = _habits[i];
                          final v = _values[h.id!];
                          final done =
                              h.target != null && v != null && v >= h.target!;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Color(h.colorValue),
                              child: Icon(done ? Icons.check : Icons.remove,
                                  color: Colors.white, size: 20),
                            ),
                            title: Text(h.name),
                            subtitle: Text(
                              h.target == null
                                  ? (h.unit.isEmpty ? ' ' : '单位：${h.unit}')
                                  : '目标：${fmtNum(h.target)}${h.unit}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  v == null ? '未记录' : '${fmtNum(v)}${h.unit}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: v == null ? Colors.grey : Color(h.colorValue),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.show_chart, size: 20),
                                  onPressed: () => _openChart(h),
                                  tooltip: '查看折线图',
                                ),
                              ],
                            ),
                            onTap: () => _editValue(h),
                            onLongPress: () async {
                              final a = await showModalBottomSheet<String>(
                                context: context,
                                builder: (ctx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.edit),
                                        title: const Text('编辑'),
                                        onTap: () => Navigator.pop(ctx, 'edit'),
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.delete,
                                            color: Colors.red),
                                        title: const Text('删除',
                                            style: TextStyle(color: Colors.red)),
                                        onTap: () => Navigator.pop(ctx, 'del'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              if (a == 'edit') _openEditor(h);
                              if (a == 'del') _confirmDelete(h);
                            },
                          );
                        },
                      ),
              ),
      );
}
class EditHabitPage extends StatefulWidget {
  final Habit? habit;
  const EditHabitPage({super.key, this.habit});
  @override
  State<EditHabitPage> createState() => _EditHabitPageState();
}

class _EditHabitPageState extends State<EditHabitPage> {
  late TextEditingController _name;
  late TextEditingController _unit;
  late TextEditingController _target;
  late bool _remind;
  late TimeOfDay _time;
  late int _color;

  static const _colors = [
    0xFF4CAF50, 0xFF2196F3, 0xFFFF9800, 0xFFE91E63,
    0xFF9C27B0, 0xFF00BCD4, 0xFF795548, 0xFF607D8B,
  ];

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _name = TextEditingController(text: h?.name ?? '');
    _unit = TextEditingController(text: h?.unit ?? '');
    _target = TextEditingController(text: fmtNum(h?.target));
    _remind = h?.remindEnabled ?? false;
    _time = TimeOfDay(hour: h?.remindHour ?? 21, minute: h?.remindMinute ?? 0);
    _color = h?.colorValue ?? _colors.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称不能为空')));
      return;
    }
    final target = _target.text.trim().isEmpty
        ? null
        : double.tryParse(_target.text.trim());
    final h = Habit(
      id: widget.habit?.id,
      name: name,
      unit: _unit.text.trim(),
      target: target,
      remindEnabled: _remind,
      remindHour: _time.hour,
      remindMinute: _time.minute,
      colorValue: _color,
      sortOrder: widget.habit?.sortOrder ?? 0,
      createdAt: widget.habit?.createdAt,
    );
    int id;
    if (h.id == null) {
      id = await DB.insertHabit(h);
    } else {
      await DB.updateHabit(h);
      id = h.id!;
    }
    await Notif.schedule(Habit(
      id: id,
      name: h.name,
      unit: h.unit,
      target: h.target,
      remindEnabled: h.remindEnabled,
      remindHour: h.remindHour,
      remindMinute: h.remindMinute,
      colorValue: h.colorValue,
      sortOrder: h.sortOrder,
      createdAt: h.createdAt,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.habit == null ? '新建打卡项' : '编辑打卡项'),
          actions: [
            TextButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '名称', hintText: '如：喝水、跑步、考试'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                  labelText: '单位（可选）', hintText: '如：杯、公里、分数、个'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '每日目标（可选）', hintText: '如：8、100'),
            ),
            const SizedBox(height: 24),
            Row(children: [
              const Text('每日提醒', style: TextStyle(fontSize: 16)),
              const Spacer(),
              Switch(
                  value: _remind,
                  onChanged: (v) => setState(() => _remind = v)),
            ]),
            if (_remind)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('提醒时间'),
                trailing: Text(
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 16),
                ),
                onTap: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
              ),
            const SizedBox(height: 24),
            const Text('颜色', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: _colors
                  .map((c) => GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: _color == c
                                ? Border.all(color: Colors.black, width: 3)
                                : null,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      );
}

class ChartPage extends StatefulWidget {
  final Habit habit;
  const ChartPage({super.key, required this.habit});
  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  int _days = 30;
  List<Map<String, Object?>> _records = [];
  bool _loading = true;
  bool _byCount = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<Map<String, Object?>> rs;
    if (_byCount) {
      rs = await DB.allValues(widget.habit.id!);
    } else {
      rs = await DB.rangeValues(widget.habit.id!, _days);
    }
    setState(() {
      _records = rs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    return Scaffold(
      appBar: AppBar(title: Text('${h.name} · 折线图')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('按天数统计')),
                      ButtonSegment(value: true, label: Text('按次数统计')),
                    ],
                    selected: {_byCount},
                    onSelectionChanged: (s) {
                      setState(() => _byCount = s.first);
                      _load();
                    },
                  ),
                ),
                if (!_byCount)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('近 7 天')),
                        ButtonSegment(value: 30, label: Text('近 30 天')),
                        ButtonSegment(value: 90, label: Text('近 90 天')),
                      ],
                      selected: {_days},
                      onSelectionChanged: (s) {
                        setState(() => _days = s.first);
                        _load();
                      },
                    ),
                  ),
                Expanded(
                  child: _records.isEmpty
                      ? const Center(
                          child: Text('这个时间段还没有打卡记录',
                              style: TextStyle(color: Colors.grey)))
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: true),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 36,
                                    getTitlesWidget: (v, _) => Text(
                                      v.toInt().toString(),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ),
                                rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    interval: _byCount
                                        ? (_records.length / 6)
                                            .clamp(1, 30)
                                            .toDouble()
                                        : (_days / 6).clamp(1, 30).toDouble(),
                                    getTitlesWidget: (v, _) {
                                      final i = v.toInt();
                                      if (i < 0 || i >= _records.length) {
                                        return const SizedBox();
                                      }
                                      if (_byCount) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            '第${i + 1}次',
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                        );
                                      } else {
                                        final d = DateTime.parse(
                                            _records[i]['date'] as String);
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            '${d.month}/${d.day}',
                                            style:
                                                const TextStyle(fontSize: 10),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _records
                                      .asMap()
                                      .entries
                                      .map((e) => FlSpot(
                                            e.key.toDouble(),
                                            (e.value['value'] as num)
                                                .toDouble(),
                                          ))
                                      .toList(),
                                  isCurved: false,
                                  color: Color(h.colorValue),
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Color(h.colorValue)
                                        .withOpacity(0.15),
                                  ),
                                ),
                                if (h.target != null)
                                  LineChartBarData(
                                    spots: [
                                      FlSpot(0, h.target!),
                                      FlSpot((_records.length - 1)
                                          .toDouble(), h.target!),
                                    ],
                                    isCurved: false,
                                    color: Colors.red.withOpacity(0.7),
                                    barWidth: 2,
                                    dashArray: [6, 6],
                                    dotData: const FlDotData(show: false),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
                if (_records.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      h.target == null
                          ? '共 ${_records.length} 条记录'
                          : '共 ${_records.length} 条记录 · 红色虚线为目标 ${fmtNum(h.target)}${h.unit}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  Map<String, int> _counts = {};
  Set<String> _memoDates = {};
  int _totalHabits = 0;

  @override
  void initState() {
    super.initState();
    _loadMonth(_focused);
  }

  Future<void> _loadMonth(DateTime d) async {
    final ym = DateFormat('yyyy-MM').format(d);
    final c = await DB.monthCounts(ym);
    final m = await DB.memoDates(ym);
    final hs = await DB.habits();
    setState(() {
      _counts = c;
      _memoDates = m;
      _totalHabits = hs.length;
    });
  }

  Color _dotColor(int count) {
    if (_totalHabits == 0) return Colors.grey;
    final r = count / _totalHabits;
    if (r >= 1) return const Color(0xFF4CAF50);
    if (r >= 0.5) return const Color(0xFFFF9800);
    return const Color(0xFFE57373);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('日历')),
        body: Column(children: [
          TableCalendar(
            firstDay: DateTime(2020, 1, 1),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            onDaySelected: (sel, foc) {
              setState(() {
                _selected = sel;
                _focused = foc;
              });
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DayDetailPage(date: sel)),
              ).then((_) => _loadMonth(_focused));
            },
            onPageChanged: (foc) {
              _focused = foc;
              _loadMonth(foc);
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (ctx, day, events) {
                final key = fmtDate(day);
                final c = _counts[key] ?? 0;
                final hasMemo = _memoDates.contains(key);
                if (c == 0 && !hasMemo) return null;
                return Positioned(
                  bottom: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c > 0)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: _dotColor(c), shape: BoxShape.circle),
                        ),
                      if (hasMemo) ...[
                        const SizedBox(width: 2),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: Colors.blue, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
                '绿点=全部完成  橙点=过半  红点=一部分  蓝点=有备忘录',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ]),
      );
}

class DayDetailPage extends StatefulWidget {
  final DateTime date;
  const DayDetailPage({super.key, required this.date});
  @override
  State<DayDetailPage> createState() => _DayDetailPageState();
}

class _DayDetailPageState extends State<DayDetailPage> {
  List<Habit> _habits = [];
  Map<int, double> _values = {};
  List<Map<String, Object?>> _memos = [];
  bool _loading = true;

  String get _dateStr => fmtDate(widget.date);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final hs = await DB.habits();
    final vs = await DB.valuesOf(_dateStr);
    final ms = await DB.memosOf(_dateStr);
    setState(() {
      _habits = hs;
      _values = vs;
      _memos = ms;
      _loading = false;
    });
  }

  Future<void> _editValue(Habit h) async {
    final cur = _values[h.id!];
    final ctrl = TextEditingController(text: fmtNum(cur));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(h.name),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration:
              InputDecoration(suffixText: h.unit.isEmpty ? null : h.unit),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, '__clear__'),
              child: const Text('清除')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (r == null) return;
    if (r == '__clear__') {
      await DB.setValue(h.id!, _dateStr, null);
    } else {
      final v = double.tryParse(r.trim());
      if (v == null) return;
      await DB.setValue(h.id!, _dateStr, v);
    }
    await _load();
  }

  Future<void> _addMemo() async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增备忘录'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: '写点什么...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (r != null && r.trim().isNotEmpty) {
      await DB.addMemo(_dateStr, r.trim());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_dateStr)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('打卡记录',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_habits.isEmpty)
                    const Text('还没有打卡项',
                        style: TextStyle(color: Colors.grey))
                  else
                    ..._habits.map((h) {
                      final v = _values[h.id!];
                      final done =
                          h.target != null && v != null && v >= h.target!;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Color(h.colorValue),
                          child: Icon(done ? Icons.check : Icons.remove,
                              color: Colors.white, size: 20),
                        ),
                        title: Text(h.name),
                        trailing: Text(
                          v == null ? '未记录' : '${fmtNum(v)}${h.unit}',
                          style: TextStyle(
                            color:
                                v == null ? Colors.grey : Color(h.colorValue),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () => _editValue(h),
                      );
                    }),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Text('备忘录',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(
                        onPressed: _addMemo,
                        icon: const Icon(Icons.add),
                        label: const Text('新增')),
                  ]),
                  if (_memos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('还没有备忘录',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._memos.map((m) => Card(
                          child: ListTile(
                            title: Text(m['content'] as String),
                            subtitle: Text(DateFormat('HH:mm').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                    m['updatedAt'] as int))),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await DB.deleteMemo(m['id'] as int);
                                await _load();
                              },
                            ),
                            onTap: () async {
                              final ctrl = TextEditingController(
                                  text: m['content'] as String);
                              final r = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('编辑备忘录'),
                                  content: TextField(
                                      controller: ctrl,
                                      maxLines: 4,
                                      autofocus: true),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('取消')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, ctrl.text),
                                        child: const Text('保存')),
                                  ],
                                ),
                              );
                              if (r != null && r.trim().isNotEmpty) {
                                await DB.updateMemo(m['id'] as int, r.trim());
                                await _load();
                              }
                            },
                          ),
                        )),
                ],
              ),
      );
}
