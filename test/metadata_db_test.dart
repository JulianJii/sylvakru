import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/data/database.dart';

/// v3 时期的表结构：没有 order_index，顺序由 rowid 隐式承载。
const _v3Schema = '''
CREATE TABLE metadata_items (
  id TEXT NOT NULL PRIMARY KEY,
  modified INTEGER,
  format TEXT,
  title TEXT,
  artist TEXT,
  album TEXT,
  album_artist TEXT,
  genre TEXT,
  year INTEGER,
  track INTEGER,
  disc INTEGER,
  bitrate INTEGER,
  samplerate INTEGER,
  duration INTEGER,
  lyrics TEXT,
  play_count INTEGER NOT NULL DEFAULT 0,
  last_played INTEGER
);
''';

MetadataItemsCompanion row(String id, int orderIndex, {String? title}) {
  return MetadataItemsCompanion.insert(
    id: id,
    orderIndex: Value(orderIndex),
    title: Value(title ?? id),
    lyrics: Value('lyrics-$id'),
    playCount: const Value(7),
  );
}

Future<List<String>> readOrder(MetadataDB db) async {
  final rows = await (db.select(
    db.metadataItems,
  )..orderBy([(t) => OrderingTerm.asc(t.orderIndex)])).get();
  return rows.map((e) => e.id).toList();
}

void main() {
  test('v3 升级到 v4：按 rowid 回填 order_index，曲库顺序保持不变', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        raw.execute(_v3Schema);
        // 故意用不是字典序的顺序写入，一旦回填出错就会被断言抓到。
        raw.execute("INSERT INTO metadata_items (id, title) VALUES ('c', 'C')");
        raw.execute("INSERT INTO metadata_items (id, title) VALUES ('a', 'A')");
        raw.execute("INSERT INTO metadata_items (id, title) VALUES ('b', 'B')");
        raw.execute('PRAGMA user_version = 3');
      },
    );

    final db = MetadataDB(executor);
    addTearDown(db.close);

    expect(await readOrder(db), ['c', 'a', 'b']);
  });

  test('全量写入：upsert 已有行时不会清空其它字段', () async {
    final db = MetadataDB(NativeDatabase.memory());
    addTearDown(db.close);

    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(db.metadataItems, [
        row('x', 0),
        row('y', 1),
      ]);
    });

    // 重排后第二次全量写入，只改下标，内容应原样保留。
    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(db.metadataItems, [
        row('y', 0),
        row('x', 1),
      ]);
    });

    expect(await readOrder(db), ['y', 'x']);

    final x = await (db.select(
      db.metadataItems,
    )..where((t) => t.id.equals('x'))).getSingle();
    expect(x.title, 'x');
    expect(x.lyrics, 'lyrics-x');
    expect(x.playCount, 7);
  });

  test('删除消失的行：只删差集，其余行保持', () async {
    final db = MetadataDB(NativeDatabase.memory());
    addTearDown(db.close);

    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(db.metadataItems, [
        row('a', 0),
        row('b', 1),
        row('c', 2),
      ]);
    });

    await (db.delete(db.metadataItems)..where((t) => t.id.isIn(['b']))).go();

    expect(await readOrder(db), ['a', 'c']);
    final remaining = await db.select(db.metadataItems).get();
    expect(remaining.length, 2);
  });
}
