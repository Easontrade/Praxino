// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SubscriptionRowsTable extends SubscriptionRows
    with TableInfo<$SubscriptionRowsTable, SubscriptionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubscriptionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rulesJsonMeta = const VerificationMeta(
    'rulesJson',
  );
  @override
  late final GeneratedColumn<String> rulesJson = GeneratedColumn<String>(
    'rules_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    url,
    name,
    enabled,
    etag,
    fetchedAt,
    rulesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subscription_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubscriptionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    }
    if (data.containsKey('rules_json')) {
      context.handle(
        _rulesJsonMeta,
        rulesJson.isAcceptableOrUnknown(data['rules_json']!, _rulesJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  SubscriptionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubscriptionRow(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      ),
      rulesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rules_json'],
      )!,
    );
  }

  @override
  $SubscriptionRowsTable createAlias(String alias) {
    return $SubscriptionRowsTable(attachedDatabase, alias);
  }
}

class SubscriptionRow extends DataClass implements Insertable<SubscriptionRow> {
  final String url;
  final String name;
  final bool enabled;
  final String? etag;
  final DateTime? fetchedAt;
  final String rulesJson;
  const SubscriptionRow({
    required this.url,
    required this.name,
    required this.enabled,
    this.etag,
    this.fetchedAt,
    required this.rulesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['name'] = Variable<String>(name);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || fetchedAt != null) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt);
    }
    map['rules_json'] = Variable<String>(rulesJson);
    return map;
  }

  SubscriptionRowsCompanion toCompanion(bool nullToAbsent) {
    return SubscriptionRowsCompanion(
      url: Value(url),
      name: Value(name),
      enabled: Value(enabled),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      fetchedAt: fetchedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(fetchedAt),
      rulesJson: Value(rulesJson),
    );
  }

  factory SubscriptionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubscriptionRow(
      url: serializer.fromJson<String>(json['url']),
      name: serializer.fromJson<String>(json['name']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      etag: serializer.fromJson<String?>(json['etag']),
      fetchedAt: serializer.fromJson<DateTime?>(json['fetchedAt']),
      rulesJson: serializer.fromJson<String>(json['rulesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'name': serializer.toJson<String>(name),
      'enabled': serializer.toJson<bool>(enabled),
      'etag': serializer.toJson<String?>(etag),
      'fetchedAt': serializer.toJson<DateTime?>(fetchedAt),
      'rulesJson': serializer.toJson<String>(rulesJson),
    };
  }

  SubscriptionRow copyWith({
    String? url,
    String? name,
    bool? enabled,
    Value<String?> etag = const Value.absent(),
    Value<DateTime?> fetchedAt = const Value.absent(),
    String? rulesJson,
  }) => SubscriptionRow(
    url: url ?? this.url,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    etag: etag.present ? etag.value : this.etag,
    fetchedAt: fetchedAt.present ? fetchedAt.value : this.fetchedAt,
    rulesJson: rulesJson ?? this.rulesJson,
  );
  SubscriptionRow copyWithCompanion(SubscriptionRowsCompanion data) {
    return SubscriptionRow(
      url: data.url.present ? data.url.value : this.url,
      name: data.name.present ? data.name.value : this.name,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      etag: data.etag.present ? data.etag.value : this.etag,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      rulesJson: data.rulesJson.present ? data.rulesJson.value : this.rulesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubscriptionRow(')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('etag: $etag, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rulesJson: $rulesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(url, name, enabled, etag, fetchedAt, rulesJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubscriptionRow &&
          other.url == this.url &&
          other.name == this.name &&
          other.enabled == this.enabled &&
          other.etag == this.etag &&
          other.fetchedAt == this.fetchedAt &&
          other.rulesJson == this.rulesJson);
}

class SubscriptionRowsCompanion extends UpdateCompanion<SubscriptionRow> {
  final Value<String> url;
  final Value<String> name;
  final Value<bool> enabled;
  final Value<String?> etag;
  final Value<DateTime?> fetchedAt;
  final Value<String> rulesJson;
  final Value<int> rowid;
  const SubscriptionRowsCompanion({
    this.url = const Value.absent(),
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.etag = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rulesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubscriptionRowsCompanion.insert({
    required String url,
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.etag = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rulesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : url = Value(url);
  static Insertable<SubscriptionRow> custom({
    Expression<String>? url,
    Expression<String>? name,
    Expression<bool>? enabled,
    Expression<String>? etag,
    Expression<DateTime>? fetchedAt,
    Expression<String>? rulesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (etag != null) 'etag': etag,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rulesJson != null) 'rules_json': rulesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubscriptionRowsCompanion copyWith({
    Value<String>? url,
    Value<String>? name,
    Value<bool>? enabled,
    Value<String?>? etag,
    Value<DateTime?>? fetchedAt,
    Value<String>? rulesJson,
    Value<int>? rowid,
  }) {
    return SubscriptionRowsCompanion(
      url: url ?? this.url,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      etag: etag ?? this.etag,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rulesJson: rulesJson ?? this.rulesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rulesJson.present) {
      map['rules_json'] = Variable<String>(rulesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubscriptionRowsCompanion(')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('etag: $etag, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rulesJson: $rulesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SubscriptionRowsTable subscriptionRows = $SubscriptionRowsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [subscriptionRows];
}

typedef $$SubscriptionRowsTableCreateCompanionBuilder =
    SubscriptionRowsCompanion Function({
      required String url,
      Value<String> name,
      Value<bool> enabled,
      Value<String?> etag,
      Value<DateTime?> fetchedAt,
      Value<String> rulesJson,
      Value<int> rowid,
    });
typedef $$SubscriptionRowsTableUpdateCompanionBuilder =
    SubscriptionRowsCompanion Function({
      Value<String> url,
      Value<String> name,
      Value<bool> enabled,
      Value<String?> etag,
      Value<DateTime?> fetchedAt,
      Value<String> rulesJson,
      Value<int> rowid,
    });

class $$SubscriptionRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SubscriptionRowsTable> {
  $$SubscriptionRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rulesJson => $composableBuilder(
    column: $table.rulesJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SubscriptionRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubscriptionRowsTable> {
  $$SubscriptionRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rulesJson => $composableBuilder(
    column: $table.rulesJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SubscriptionRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubscriptionRowsTable> {
  $$SubscriptionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get rulesJson =>
      $composableBuilder(column: $table.rulesJson, builder: (column) => column);
}

class $$SubscriptionRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubscriptionRowsTable,
          SubscriptionRow,
          $$SubscriptionRowsTableFilterComposer,
          $$SubscriptionRowsTableOrderingComposer,
          $$SubscriptionRowsTableAnnotationComposer,
          $$SubscriptionRowsTableCreateCompanionBuilder,
          $$SubscriptionRowsTableUpdateCompanionBuilder,
          (
            SubscriptionRow,
            BaseReferences<
              _$AppDatabase,
              $SubscriptionRowsTable,
              SubscriptionRow
            >,
          ),
          SubscriptionRow,
          PrefetchHooks Function()
        > {
  $$SubscriptionRowsTableTableManager(
    _$AppDatabase db,
    $SubscriptionRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubscriptionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubscriptionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubscriptionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<DateTime?> fetchedAt = const Value.absent(),
                Value<String> rulesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubscriptionRowsCompanion(
                url: url,
                name: name,
                enabled: enabled,
                etag: etag,
                fetchedAt: fetchedAt,
                rulesJson: rulesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                Value<String> name = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<DateTime?> fetchedAt = const Value.absent(),
                Value<String> rulesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubscriptionRowsCompanion.insert(
                url: url,
                name: name,
                enabled: enabled,
                etag: etag,
                fetchedAt: fetchedAt,
                rulesJson: rulesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SubscriptionRowsTable, SubscriptionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SubscriptionRowsTable,
                    SubscriptionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SubscriptionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubscriptionRowsTable,
      SubscriptionRow,
      $$SubscriptionRowsTableFilterComposer,
      $$SubscriptionRowsTableOrderingComposer,
      $$SubscriptionRowsTableAnnotationComposer,
      $$SubscriptionRowsTableCreateCompanionBuilder,
      $$SubscriptionRowsTableUpdateCompanionBuilder,
      (
        SubscriptionRow,
        BaseReferences<_$AppDatabase, $SubscriptionRowsTable, SubscriptionRow>,
      ),
      SubscriptionRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SubscriptionRowsTableTableManager get subscriptionRows =>
      $$SubscriptionRowsTableTableManager(_db, _db.subscriptionRows);
}
