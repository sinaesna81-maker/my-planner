import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const PlannerApp());

String fa(Object n) => n.toString().replaceAllMapped(
    RegExp(r'\d'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);

class Att {
  String name, path;
  Att(this.name, this.path);
  Map toJson() => {'n': name, 'p': path};
  static Att from(Map j) => Att(j['n'], j['p']);
}

class Item {
  String id, title, desc, date; // date: ISO yyyy-MM-dd or ''
  bool done;
  List<Att> files;
  Item(this.title,
      {String? id, this.desc = '', this.done = false, this.date = '', List<Att>? files})
      : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        files = files ?? [];
  Map toJson() => {
        'i': id, 't': title, 'd': desc, 'x': done, 'dt': date,
        'f': files.map((e) => e.toJson()).toList()
      };
  static Item from(Map j) => Item(j['t'],
      id: j['i'], desc: j['d'], done: j['x'], date: j['dt'],
      files: (j['f'] as List).map((e) => Att.from(e)).toList());
}

class PlannerApp extends StatelessWidget {
  const PlannerApp({super.key});
  @override
  Widget build(BuildContext context) {
    ThemeData th(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1C1C1A), brightness: b));
    return MaterialApp(
      title: 'My planner',
      debugShowCheckedModeBanner: false,
      theme: th(Brightness.light),
      darkTheme: th(Brightness.dark),
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  SharedPreferences? prefs;
  Map<String, List<Item>> tasks = {};
  List<Item> goals = [];
  int tab = 0, week = 0;
  late DateTime sel;
  final q = TextEditingController();
  static const wd = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    sel = DateTime(n.year, n.month, n.day);
    _load();
  }

  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();
    final raw = prefs!.getString('mp');
    if (raw != null) {
      final j = jsonDecode(raw);
      tasks = (j['tasks'] as Map).map((k, v) =>
          MapEntry(k as String, (v as List).map((e) => Item.from(e)).toList()));
      goals = (j['goals'] as List).map((e) => Item.from(e)).toList();
    }
    setState(() {});
  }

  void _save() => prefs?.setString(
      'mp',
      jsonEncode({
        'tasks': tasks.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
        'goals': goals.map((e) => e.toJson()).toList()
      }));

  String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
  DateTime _weekStart() {
    final n = DateTime.now();
    final t = DateTime(n.year, n.month, n.day);
    return t.subtract(Duration(days: (t.weekday + 1) % 7)).add(Duration(days: 7 * week));
  }

  List<Item> get _list => tab == 0 ? (tasks[_key(sel)] ??= []) : goals;

  void _add() {
    final v = q.text.trim();
    if (v.isEmpty) return;
    setState(() => _list.add(Item(v)));
    q.clear();
    _save();
  }

  Future<void> _edit(Item it) async {
    final t = TextEditingController(text: it.title);
    final d = TextEditingController(text: it.desc);
    var date = it.date;
    final files = [...it.files];
    final list = _list;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: t, decoration: const InputDecoration(labelText: 'عنوان', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: d, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder())),
              if (tab == 1) ...[
                const SizedBox(height: 8),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(date.isEmpty ? 'تاریخ (اختیاری)' : _fmt(DateTime.parse(date))),
                    onPressed: () async {
                      final p = await showDatePicker(
                          context: c,
                          initialDate: date.isEmpty ? DateTime.now() : DateTime.parse(date),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (p != null) ss(() => date = p.toIso8601String().substring(0, 10));
                    },
                  ),
                  if (date.isNotEmpty) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => ss(() => date = '')),
                ]),
              ],
              const SizedBox(height: 4),
              for (final f in files)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(f.name, overflow: TextOverflow.ellipsis),
                  onTap: () => OpenFilex.open(f.path),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => ss(() => files.remove(f))),
                ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('افزودن پیوست'),
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(allowMultiple: true);
                  if (r == null) return;
                  final dir = await getApplicationDocumentsDirectory();
                  for (final f in r.files) {
                    if (f.path == null) continue;
                    final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_${f.name}';
                    await File(f.path!).copy(dest);
                    files.add(Att(f.name, dest));
                  }
                  ss(() {});
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    list.remove(it);
                    Navigator.pop(c);
                  },
                  child: const Text('حذف'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    for (final o in it.files) {
                      if (!files.any((f) => f.path == o.path)) File(o.path).delete().catchError((_) => File(o.path));
                    }
                    it.title = t.text.trim().isEmpty ? it.title : t.text.trim();
                    it.desc = d.text.trim();
                    it.date = date;
                    it.files = files;
                    Navigator.pop(c);
                  },
                  child: const Text('ذخیره'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    setState(() {});
    _save();
  }

  String _fmt(DateTime d) {
    final j = Jalali.fromDateTime(d);
    return fa('${j.day} ${j.formatter.mN} ${j.year}');
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => _weekStart().add(Duration(days: i)));
    final mid = Jalali.fromDateTime(days[3]);
    final list = _list;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My planner', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: tab == 0
            ? [
                IconButton(icon: const Text('›', style: TextStyle(fontSize: 26)), onPressed: () => _shift(-1)),
                Text(fa('${mid.formatter.mN} ${mid.year}'), style: const TextStyle(fontSize: 13)),
                IconButton(icon: const Text('‹', style: TextStyle(fontSize: 26)), onPressed: () => _shift(1)),
              ]
            : null,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'روزانه'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'اهداف بلندمدت'),
        ],
      ),
      body: Column(children: [
        if (tab == 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => sel = days[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _key(days[i]) == _key(sel) ? cs.primary : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(children: [
                        Text(wd[i], style: TextStyle(fontSize: 12, color: _key(days[i]) == _key(sel) ? cs.onPrimary : cs.outline)),
                        Text(fa(Jalali.fromDateTime(days[i]).day),
                            style: TextStyle(fontWeight: FontWeight.w600, color: _key(days[i]) == _key(sel) ? cs.onPrimary : null)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: q,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              hintText: tab == 0 ? 'تسک جدید…' : 'هدف جدید…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(tab == 0 ? 'برای این روز تسکی نداری' : 'هنوز هدفی ننوشتی', style: TextStyle(color: cs.outline)))
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: list.length,
                  onReorder: (a, b) {
                    if (b > a) b--;
                    setState(() => list.insert(b, list.removeAt(a)));
                    _save();
                  },
                  itemBuilder: (c, i) {
                    final it = list[i];
                    final meta = [
                      if (it.date.isNotEmpty) '🗓 ${_fmt(DateTime.parse(it.date))}',
                      if (it.desc.isNotEmpty) '✎',
                      if (it.files.isNotEmpty) '📎 ${fa(it.files.length)}',
                    ].join(' · ');
                    return Card(
                      key: ValueKey(it.id),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
                      child: ListTile(
                        leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                        title: Text(it.title, style: TextStyle(decoration: it.done ? TextDecoration.lineThrough : null, color: it.done ? cs.outline : null)),
                        subtitle: meta.isEmpty ? null : Text(meta, style: const TextStyle(fontSize: 12)),
                        trailing: Checkbox(
                          shape: const CircleBorder(),
                          value: it.done,
                          onChanged: (v) {
                            setState(() => it.done = v ?? false);
                            _save();
                          },
                        ),
                        onTap: () => _edit(it),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  void _shift(int n) => setState(() {
        week += n;
        sel = _weekStart();
      });
}
