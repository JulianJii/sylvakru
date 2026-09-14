import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class MetadataItems extends Table {
  TextColumn get id => text()();

  /// 曲库中的显示顺序。此前没有这一列，顺序是靠在整表重写时重新分配
  /// rowid 隐式保存的，重排因此必须重写每一行。显式存下来之后，
  /// 重排只需要更新下标发生平移的那一段。
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  IntColumn get modified => integer().nullable()();

  TextColumn get format => text().nullable()();

  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get genre => text().nullable()();

  IntColumn get year => integer().nullable()();
  IntColumn get track => integer().nullable()();
  IntColumn get disc => integer().nullable()();

  IntColumn get bitrate => integer().nullable()();
  IntColumn get samplerate => integer().nullable()();
  IntColumn get duration => integer().nullable()();

  TextColumn get lyrics => text().nullable()();

  IntColumn get playCount => integer().withDefault(const Constant(0))();

  IntColumn get lastPlayed => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [MetadataItems])
class MetadataDB extends _$MetadataDB {
  MetadataDB(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(metadataItems, metadataItems.albumArtist);
        }

        if (from < 3) {
          await m.dropColumn(metadataItems, 'source_type');
        }

        if (from < 4) {
          await m.addColumn(metadataItems, metadataItems.orderIndex);
          // 旧库的顺序原本由 rowid 承载，按 rowid 回填即可让升级前后
          // 读出来的曲库顺序完全一致。
          await customStatement('UPDATE metadata_items SET order_index = rowid');
        }
      },
    );
  }
}

LazyDatabase openMetadataDB(String name) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();

    final file = File(p.join(dir.path, name));

    return NativeDatabase.createInBackground(file);
  });
}
