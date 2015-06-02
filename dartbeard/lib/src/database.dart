library dartbeard.database;

import "dart:async";
import 'package:postgresql/pool.dart';
import 'package:postgresql/postgresql.dart';

import "tvdb.dart";

import 'package:models/models.dart';



class Database {

  PoolSettings settings;
  Pool pool;
  Connection listenConn;

  StreamController _changes = new StreamController.broadcast();
  Stream get changes => _changes.stream;

  Map<int, Map> seriesCache = {};
  Map<int, List<Map>> seriesEpisodesCache = {};

  List<String> seriesFields;
  List<String> episodeFields;
  List<String> torrentFields;

  Database() {
    // Fun way to get a list of valid fields on the model.
    Series s = new Series();
    Episode e = new Episode();
    Torrent t = new Torrent();
    seriesFields = s.toMap().keys.where((f) => f != 'episodes').toList();
    episodeFields = e.toMap().keys.toList();
    torrentFields = t.toMap().keys.toList();
  }

  Future start(String databaseUri) async {

    settings = new PoolSettings(
        databaseUri: databaseUri,
        maxConnections: 5,
        minConnections: 2
    );
    if (pool != null) {
      await pool.stop();
    }

    pool = new Pool.fromSettings(settings);
    await pool.start();

    if (listenConn != null) {
      listenConn.close();
    }

    listenConn = await connect(this.settings.databaseUri);
    listenConn.channel("changes").listen(_onChangeEvent);
  }

  void _onChangeEvent(event) {
    List<String> parts = event.payload.split(' ');
    String action = parts[0];
    String model = parts[1];
    if (model == 'series') {
      int pk = int.parse(parts[2]);
      seriesCache.remove(pk);
    } else if (model == 'episode') {
      int seriesId = int.parse(parts[3]);
      seriesCache.remove(seriesId);
      seriesEpisodesCache.remove(seriesId);
    }
    _changes.add(event);
  }

  Future getConnection() async {
    return pool.connect();
  }


  Future<bool> seriesExists(int seriesId) async {
    var conn = await getConnection();
    List results = await conn.query("SELECT id from series where id = @id limit 1", {'id': seriesId}).toList();
    conn.close();
    return results.length == 1;

  }

  Future<List<String>> getAllSeriesDirectories() async {
    var conn = await getConnection();
    List<String> results = await conn.query("""SELECT DISTINCT "libraryLocation" from series""").map((row) => row.libraryLocation).toList();
    conn.close();
    return results;
  }

  Future getAllSeries() async {
    var conn = await getConnection();

    var results = await conn.query("""SELECT *,
      (select count(id) from episode where "seriesId" = st.id and "libraryLocation" is not null) as "downloadedEpisodes",
      (select count(id) from episode where "seriesId" = st.id and "firstAired" is not null and status != 'Ignored') as "knownEpisodes" from series st"""
    ).map(
            (row) => new Series.fromMap(row.toMap())
    ).toList();
    conn.close();
    return results;
  }

  Future getSeries(int seriesId) async {

    if (seriesCache.containsKey(seriesId)) {
      return new Series.fromMap(seriesCache[seriesId]);
    }

    var conn = await getConnection();
    var result = await conn.query("""SELECT *,
      (select count(id) from episode where "seriesId" = st.id and "libraryLocation" is not null) as "downloadedEpisodes",
      (select count(id) from episode where "seriesId" = st.id and "firstAired" is not null and status != 'Ignored') as "knownEpisodes" from series
      st where id = @seriesId limit 1""", {'seriesId': seriesId}).map((row) => new Series.fromMap(row.toMap())).toList();
    conn.close();
    if (result.length == 0) {
      return null;
    }

    Series s = result.first;
    seriesCache[s.id] = s.toMap();
    return s;
  }

  Future getSeriesByLibraryLocation(String libraryLocation) async {
    var conn = await getConnection();
    var result = await conn.query("""SELECT *,
      (select count(id) from episode where "seriesId" = st.id and "libraryLocation" is not null) as "downloadedEpisodes",
      (select count(id) from episode where "seriesId" = st.id and "firstAired" is not null and status != 'Ignored') as "knownEpisodes" from series
      st where "libraryLocation" = @ll limit 1""", {'ll': libraryLocation}).map((row) => new Series.fromMap(row.toMap())).toList();
    conn.close();
    if (result.length == 0) {
      return null;
    }
    return result.first;
  }

  Future<List<Episode>> getWantedEpisodes() async {
    var conn = await getConnection();
    var results = await conn.query('''SELECT episode.* FROM episode left join series on series.id = episode."seriesId" WHERE episode.status = 'Wanted' and not series.ignore''').toList();
    results = results.map((r) => new Episode.fromMap(r.toMap())).toList();
    conn.close();
    return results;
  }

  Future<List<Torrent>> getUnprocessedTorrents() async {
    var conn = await getConnection();
    var result = conn.query('''select * from torrent where processed = 0 and "leftUntilDone" = 0 and "totalSize" > 0 and "relatedContent" is not null''');
    List<Torrent> results = await result.map((row) => new Torrent.fromMap(row.toMap())).toList();
    conn.close();
    return results;
  }

  Future insertOrUpdateTorrent(String hash, Map data) async {
    var conn = await getConnection();
    var results = await conn.query("SELECT hash from torrent where hash = @hash limit 1", {'hash': hash}).toList();
    String query;
    if (results.length == 0) {
      var vars = torrentFields.where((k) => data.containsKey(k)).map((k) => "@${k}").join(", ");
      var fields = torrentFields.where((k) => data.containsKey(k)).map((f) => '"$f"').join(", ");
      query = "insert into torrent (${fields}) VALUES (${vars});";
      print("Inserting Torrent ");
      print(data.toString());
      print("--");
    } else {
      query = "update torrent set ";
      var updates = [];
      data.forEach((k, v) {
        if (torrentFields.contains(k)) {
          updates.add('"$k" = @$k');
        }
      });
      query += updates.join(", ");
      query += " where hash = @hash";

    }
    await conn.execute(query, data);
    conn.close();
  }

  Future deleteSeries(int id) async {
    var conn = await getConnection();
    await conn.execute('delete from episode where "seriesId" = @id', {'id': id});
    await conn.execute('delete from series where "id" = @id', {'id': id});
    conn.close();
  }

  Future deleteTorrents(List<String> hashes) async {
    var conn = await getConnection();
    String hashString = hashes.map((h) => "'$h'").join(",");
    await conn.execute("delete from torrent where hash in ($hashString)");
    conn.close();
  }

  setTorrentProcessing(String hash) async {
    var conn = await getConnection();
    await conn.execute("update torrent set processed = 1 where hash = @hash", {'hash': hash});
    conn.close();
  }

  setTorrentProcessed(String hash) async {
    var conn = await getConnection();
    await conn.execute("update torrent set processed = 2 where hash = @hash", {'hash': hash});
    conn.close();
  }

  Future<Map> getBTNMeta() async {
    var conn = await getConnection();
    var results = await conn.query("select * from btn_meta limit 1").map((r) => r.toMap()).toList();
    Map meta = {};
    if (results.length == 0) {
      meta['lastTorrentTime'] = 0;
      meta['lastTorrentIds'] = '';
      await conn.execute('insert into btn_meta ("lastTorrentTime", "lastTorrentIds") values (@lastTorrentTime, @lastTorrentIds)', meta);
    } else {
      meta = results[0];
    }
    conn.close();
    return meta;
  }

  setBTNMeta(Map meta) async {
    var conn = await getConnection();
    await conn.execute('update btn_meta set "lastTorrentTime" = @lastTorrentTime, "lastTorrentIds" = @lastTorrentIds', meta);
    conn.close();
  }

  Future<Series> getSeriesNeedingUpdate() async {
    var conn = await getConnection();
    var results = await conn.query('''select *,
      (select count(id) from episode where "seriesId" = st.id and "libraryLocation" is not null) as "downloadedEpisodes",
      (select count(id) from episode where "seriesId" = st.id and "firstAired" is not null and status != 'Ignored') as "knownEpisodes"
      from series st
      where "lastUpdated" < now() - '12 hours'::interval
          and status != 'Ended' and not ignore
      order by "lastUpdated" asc limit 1''').map((row) => new Series.fromMap(row.toMap())).toList();
    conn.close();
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }


  insertOrUpdateSeries(int id, Map data) async {
    seriesCache.remove(id);
    var conn = await getConnection();
    var results = await conn.query("SELECT id from series where id = @id limit 1", {'id': id}).toList();
    String query;
    data['updating'] = true;
    if (results.length == 0) {
      var vars = seriesFields.where((k) => data.containsKey(k)).map((k) => "@${k}").join(", ");
      var fields = seriesFields.where((k) => data.containsKey(k)).map((f) => '"$f"').join(", ");
      query = "insert into series (${fields}) VALUES (${vars});";
    } else {
      query = "update series set ";
      var updates = [];
      data.forEach((k, v) {
        if (seriesFields.contains(k)) {
          updates.add('"$k" = @$k');
        }
      });

      query += updates.join(", ");
      query += " where id = @id and not updating";
    }
    int updated = await conn.execute(query, data);
    if (updated == 0) {
      // couldn't get lock?
      conn.close();
      return false;
    }
    if (data.containsKey('episodes')) {
      for (var episode in data['episodes']) {
        results = await conn.query("select id from episode where id = @id limit 1", {'id': episode["id"]}).toList();
        data = episode;
        var query;
        if (results.length == 0) {

          var vars = episodeFields.where((k) => data.containsKey(k)).map((k) => "@${k}").join(", ");
          var fields = episodeFields.where((k) => data.containsKey(k)).map((f) => '"$f"').join(", ");

          query = "insert into episode (${fields}) VALUES (${vars});";
        } else {
          query = "update episode set ";
          var updates = [];
          data.forEach((k, v) {
            if (episodeFields.contains(k)) {
              updates.add('"$k" = @$k');
            }
          });
          query += updates.join(", ");
          query += " where id = @id";
        }
        await conn.execute(query, data);
      }
    }

    await conn.execute('UPDATE series set updating = false, "lastUpdated" = NOW() where id = @id', {'id': id});
    conn.close();
    return true;
  }

  updateEpisode(episodeId, Map data) async {
    var conn = await getConnection();
    String query = "UPDATE episode SET ";
    List<String> updates = [];
    data.forEach((k,v) {
      if (episodeFields.contains(k)) {
        updates.add('"$k" = @$k');
      }
    });
    query += updates.join(", ");
    query += " where id = @id";
    data['id'] = episodeId;
    await conn.execute(query, data);
    conn.close();
  }

  Future<List<Episode>> getEpisodes(int seriesId, [int seasonNumber = null]) async {

    if (seasonNumber == null && seriesEpisodesCache.containsKey(seriesId)) {
      return seriesEpisodesCache[seriesId].map((m) => new Episode.fromMap(m)).toList();
    }

    var conn = await getConnection();
    String and = '';
    Map params = {'id': seriesId};
    if (seasonNumber != null) {
      and = ' and "seasonNumber" = @season';
      params['season'] = seasonNumber;
    }
    List<Episode> episodes = await conn.query("""SELECT * from episode where "seriesId" = @id$and""", params).map((e) => new Episode.fromMap(e.toMap())).toList();
    if (seasonNumber == null) {
      seriesEpisodesCache[seriesId] = episodes.map((e) => e.toMap()).toList();
    }
    conn.close();
    return episodes;
  }

  setSeriesUpdating(int seriesId, bool value) async {
    seriesCache.remove(seriesId);
    var conn = await getConnection();
    await conn.execute("update series set updating = @val where id = @id", {'id': seriesId, 'val': value});
    conn.close();
  }

  Future<Episode> getEpisode(int episodeId) async {
    var conn = await getConnection();
    List<Episode> episodes = await conn.query("""SELECT * from episode where "id" = @id limit 1""", {'id': episodeId}).map((e) => new Episode.fromMap(e.toMap())).toList();
    conn.close();
    return episodes.first;
  }

  Future getUpcomingEpisodes() async {
    var conn = await getConnection();
    List<Episode> results = await conn.query("""select
            series.name as series__name,
            series.id as series__id,
            series."firstAired" as "series__firstAired",
            series.overview as series__overview,
            series."contentRating" as "series__contentRating",
            series."libraryLocation" as "series__libraryLocation",
            series.banner as "series__banner",
            series.poster as "series__poster",
            series.fanart as "series__fanart",
            series.network as "series__network",
            series.status as "series__status",
            series.updating as "series__updating",
            episode.*
            from
            series left join episode on series.id = episode."seriesId"
            where (episode."firstAired" >= CURRENT_TIMESTAMP - INTERVAL '7 days')
            and (episode."libraryLocation" is null)
            and not series.ignore
            and episode.status != 'Ignored'
            order by episode."firstAired"
    """).map((row) {
      return new Episode.fromMap(row.toMap());
    }).toList();

    conn.close();
    return results;
  }
}
