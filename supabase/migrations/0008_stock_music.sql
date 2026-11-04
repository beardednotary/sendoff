-- Sendoff — the stock music
--
-- The four reveal tracks, replacing the placeholder names from 0001. All are Creative Commons
-- Attribution, so the composer is credited wherever the music is: the reveal and the create
-- flow show only a track's title, so the title carries the name ("Home Was You · Scott Buckley",
-- like a linked song's "Title · Artist"), and the full credit with each license is on
-- sendoffapp.com/support (web/app/src/site/info.ts).
--
--   warm        "Home Was You"         Scott Buckley  CC BY 4.0     scottbuckley.com.au
--   bright      "Simplicity"           Scott Buckley  CC BY 4.0     scottbuckley.com.au
--   reflective  "Acoustic Meditation"  Jason Shaw     CC BY 3.0 US  audionautix.com
--   triumphant  "Victor Lux"           Scott Buckley  CC BY 4.0     scottbuckley.com.au
--
-- The audio itself is not in the repo: supabase/setup.sh uploads supabase/stock-music/*.m4a to
-- the stock-music bucket.

update music_tracks set title = 'Home Was You · Scott Buckley', artist = 'Scott Buckley', duration_seconds = 269
 where id = 'warm_piano';
update music_tracks set title = 'Simplicity · Scott Buckley', artist = 'Scott Buckley', duration_seconds = 185
 where id = 'bright_strings';
update music_tracks set title = 'Acoustic Meditation · Jason Shaw', artist = 'Jason Shaw', duration_seconds = 195
 where id = 'reflective_guitar';
update music_tracks set title = 'Victor Lux · Scott Buckley', artist = 'Scott Buckley', duration_seconds = 202
 where id = 'triumphant_brass';
