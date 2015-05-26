--
-- series
--
create table if not exists series (
  "id" integer primary key not null,
  "name" text not null,
  "firstAired" timestamptz null,
  "airsTime" text null,
  "airsDOW" text null,
  "banner" text null,
  "poster" text null,
  "fanart" text null,
  "language" text null,
  "overview" text null,
  "network" text null,
  "status" text null,
  "imdbId" text null,
  "runTime" int null,
  "updating" bool default false,
  "contentRating" text null,
  "libraryLocation" text null,
  "renamePattern" text null,
  "preferredResolution" text null,
  "ignore" bool default false,
  "lastUpdated" timestamptz default current_timestamp
);

CREATE OR REPLACE FUNCTION tr_series_on_delete() RETURNS trigger AS $TR$
  BEGIN
    PERFORM pg_notify('changes', 'delete series ' || OLD.id);
    RETURN NEW;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS series_on_delete ON series;
CREATE TRIGGER series_on_delete AFTER DELETE ON series FOR EACH ROW EXECUTE PROCEDURE tr_series_on_delete();


CREATE OR REPLACE FUNCTION tr_series_on_insert() RETURNS trigger AS $TR$
    BEGIN
    PERFORM pg_notify('changes', 'insert series ' || NEW.id);
    RETURN NEW;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS series_on_insert ON series;
CREATE TRIGGER series_on_insert AFTER INSERT ON series FOR EACH ROW EXECUTE PROCEDURE tr_series_on_insert();

CREATE OR REPLACE FUNCTION tr_series_on_update() RETURNS trigger AS $$
my @changed = ();
for my $key ( keys $_TD->{new} ) {
  if ($_TD->{new}{$key} ne $_TD->{old}{$key}) {
    push(@changed, $key);
  }
}
my $changedStr = join(',', @changed);
elog(NOTICE, "changed = @changed changedStr = $changedStr" );
spi_exec_query("SELECT pg_notify('changes', 'update series " . $_TD->{old}{id} . " " . $changedStr . "')");
return;
$$ LANGUAGE plperl;
DROP TRIGGER IF EXISTS series_on_update ON series;
CREATE TRIGGER series_on_update AFTER UPDATE ON series FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE PROCEDURE tr_series_on_update();


--
-- episode
--
create table if not exists episode (
  "id" integer primary key not null,
  "seriesId" integer references series(id) not null,
  "name" text null,
  "director" text null,
  "writer" text null,
  "firstAired" text null,
  "overview" text null,
  "seasonNumber" int not null,
  "number" int not null,
  "image" text null,
  "libraryLocation" text null,
  "status" text not null default 'Wanted'
);

CREATE OR REPLACE FUNCTION tr_episode_on_delete() RETURNS trigger AS $TR$
    BEGIN
    PERFORM pg_notify('changes', 'delete episode ' || OLD.id || ' ' || OLD."seriesId");
    RETURN OLD;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS episode_on_delete ON episode;
CREATE TRIGGER episode_on_delete AFTER DELETE ON episode FOR EACH ROW EXECUTE PROCEDURE tr_episode_on_delete();


CREATE OR REPLACE FUNCTION tr_episode_on_insert() RETURNS trigger AS $TR$
    BEGIN
    PERFORM pg_notify('changes', 'insert episode ' || NEW.id || ' ' || NEW."seriesId");
    RETURN NEW;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS episode_on_insert ON episode;
CREATE TRIGGER episode_on_insert AFTER INSERT ON episode FOR EACH ROW EXECUTE PROCEDURE tr_episode_on_insert();


CREATE OR REPLACE FUNCTION tr_episode_on_update() RETURNS trigger AS $$
my @changed = ();
for my $key ( keys $_TD->{new} ) {
  if ($_TD->{new}{$key} ne $_TD->{old}{$key}) {
    push(@changed, $key);
  }
}
my $changedStr = join(',', @changed);
elog(NOTICE, "changed = @changed changedStr = $changedStr" );
spi_exec_query("SELECT pg_notify('changes', 'update episode " . $_TD->{old}{id} . " " . $_TD->{old}{seriesId} . " " . $changedStr . "')");
return;
$$ LANGUAGE plperl;
DROP TRIGGER IF EXISTS episode_on_update ON episode;
CREATE TRIGGER episode_on_update AFTER UPDATE ON episode FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE PROCEDURE tr_episode_on_update();

--
-- torrent
--
create table if not exists torrent (
  hash varchar(40) primary key,
  name text null,
  "errorString" text null,
  status int default 0,
  "totalPeers" int default 0,
  "connectedPeers" int default 0,
  "lastActive" timestamptz null,
  "startedAt" timestamptz null,
  "addedAt" timestamptz null,
  "finishedAt" timestamptz null,
  "downloadDir" text null,
  "rateDownload" int default 0,
  "rateUpload" int default 0,
  "totalSize" bigint default 0,
  "leftUntilDone" bigint default 0,
  "relatedContent" text null,
  "processed" int default 0
);

CREATE OR REPLACE FUNCTION tr_torrent_on_delete() RETURNS trigger AS $TR$
    BEGIN
    PERFORM pg_notify('changes', 'delete torrent ' || OLD.hash);
    RETURN OLD;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS torrent_on_delete ON torrent;
CREATE TRIGGER torrent_on_delete AFTER DELETE ON torrent FOR EACH ROW EXECUTE PROCEDURE tr_torrent_on_delete();


CREATE OR REPLACE FUNCTION tr_torrent_on_insert() RETURNS trigger AS $TR$
    BEGIN
    PERFORM pg_notify('changes', 'insert torrent ' || NEW.hash);
    RETURN NEW;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS torrent_on_insert ON torrent;
CREATE TRIGGER torrent_on_insert AFTER INSERT ON torrent FOR EACH ROW EXECUTE PROCEDURE tr_torrent_on_insert();


CREATE OR REPLACE FUNCTION tr_torrent_on_update() RETURNS trigger AS $TR$
    BEGIN
    PERFORM pg_notify('changes', 'update torrent ' || NEW.hash);
    RETURN NEW;
    END;
$TR$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS torrent_on_update ON torrent;
CREATE TRIGGER torrent_on_update AFTER UPDATE ON torrent FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE PROCEDURE tr_torrent_on_update();
