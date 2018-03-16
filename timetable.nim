import times
import os
import sequtils
import tables
import strutils
import marshal
import nimquery

type
  Location = ref object
    name*: string
    year*: BiggestInt
    valid_dates*: seq[DateTime]

  Activity = ref object
    id*: string
    day*: string
    start*: DateTime
    endtime*: DateTime
    location*: seq[Location]

  Course = ref object
    title*: string
    year*: BiggestInt
    semester*: BiggestInt
    activities*: TableRef[string, Activity]

proc `$`(x: Location): string =
  "Location($1, $2)" % [x.name, $x.year]

proc `$`(x: Activity): string =
  "Activity($1, $2, $3, $4)" % [x.id, x.day, $x.start, $x.endtime, $x.location]

proc `$`(x: Course): string =
  "Course($1, $2, $3, $4)" % [x.title, $x.year, $x.semester, $x.activities]


let course = Course(title: "test", year: 2018, semester: 1, activities: {"01":
                                                                          Activity(id: "01", day: "Monday", start: now(), endtime: now(), location: @[Location(name: "test", year: 2018, valid_dates: @[now()])])}.newTable)
echo $$course
