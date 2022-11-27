using JSON
using SQLite
using Tables
using Dates
using TimeZones


# The same point in time is represented regardless of the zone, so the system timezone is arbitrarily chosen
read_date(ts) = ZonedDateTime(Dates.unix2datetime(ts / 1_000_000), localzone(), from_utc=true)


"""
    function read_timestamps_file(path::AbstractString)::Vector{Int}
Loads timestamps of "activity" (some wakefulness indicator) as nanoseconds since Unix epoch from a supported format, currently:
- JSON
- SQLite from Firefox `places.sqlite` database
"""
function read_timestamps_file(
	path::AbstractString;
)::Vector{ZonedDateTime}
	
	isfile(path) || error("No database file found at $path")

	return if endswith(path, ".json")
		open(JSON.parse, path)
	elseif endswith(path, ".sqlite")
		db = SQLite.DB(path)
		ts = Tables.columns(DBInterface.execute(db, 
			"SELECT visit_date FROM moz_historyvisits"
		)).visit_date
		DBInterface.close!(db)
		sort!(ts)
        read_date.(ts)
	else
		error("Expects JSON or SQLite file")
	end
end

