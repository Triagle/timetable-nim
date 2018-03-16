import times
import os
import sequtils
import tables
import strutils
import marshal
import httpclient
import xmltree
import nimquery
import htmlparser
import streams

type
  Location = ref object
    name*: string
    year*: BiggestInt
    valid_dates*: seq[DateTime]

  Activity = ref object
    id*: string
    name*: string
    day*: string
    start*: DateTime
    endtime*: DateTime
    location*: seq[Location]

  Course = ref object
    title*: string
    year*: BiggestInt
    semester*: BiggestInt
    activities*: TableRef[string, seq[Activity]]

proc `$`(x: Location): string =
  "Location($1, $2)" % [x.name, $x.year]

proc `$`(x: Activity): string =
  "Activity($1, $2, $3, $4)" % [x.id, x.name, $x.start, $x.endtime, $x.location]

proc `$`(x: Course): string =
  "Course($1, $2, $3, $4)" % [x.title, $x.year, $x.semester, $x.activities]

proc parse_activity(header: XmlNode, data: XmlNode): auto =
  let
    title = header.querySelector("tbody td").inner_text
    id = data.querySelector("td[data-title^=\"Activity\"]").inner_text
    day = data.querySelector("td[data-title^=\"Day\"]").inner_text
    act_time = data.querySelector("td[data-title^=\"Time\"]").inner_text
    times = map(act_time.split({'-'}), proc (value: string): auto = parse(value.strip, "HH:mm"))

  Activity(id: id, name: title, day: day, start: times[0], endtime: times[1], location: @[])


proc get_course(code: string, year: int, semester: int): auto =
  var client = new_http_client()
  let
    url = "http://www.canterbury.ac.nz/courseinfo/GetCourseDetails.aspx?course=$1&occurrence=$2S$3(C)&year=$4" % [code, $(year mod 100), $semester, $year]
    html = parse_html(new_string_stream(client.get_content(url)))
    activity_table = html.querySelector("table#RepeatTable")

  var
    current_header: XmlNode
    activities = newTable[string,seq[Activity]]()

  for node in activity_table.items():
    echo node
    if node.kind != xnElement:
      continue
    elif node.tag() == "headertemplate":
      current_header = node
    elif node.tag() == "tr":
      let activity = parse_activity(current_header, node)
      var activity_options = activities.mget_or_put(activity.name, @[])
      activity_options.add(activity)
      activities[activity.name] = activity_options

  Course(title: code, year: year, semester: semester, activities: activities)

echo $get_course("COSC262", 2018, 1)
