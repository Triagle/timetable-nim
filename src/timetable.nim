import
  times, parsecfg, algorithm, os, sequtils, tables, strutils, marshal, httpclient,
  options, xmltree, htmlparser, streams, strformat, terminal, parseopt, ospaths
import nimquery

type
  Location = ref object
    name*: string
    year*: BiggestInt
    valid_dates*: seq[DateTime]

  Day = enum
    Monday, Tuesday, Wednesday, Thursday, Friday
    #
  Activity = ref object
    id*: string
    course*: string
    name*: string
    day*: WeekDay
    start*: DateTime
    endtime*: DateTime
    location*: seq[Location]

  Course = ref object
    title*: string
    year*: BiggestInt
    semester*: BiggestInt
    activities*: seq[Activity]

proc `$`(x: Location): string =
  "Location($1, $2)" % [x.name, $x.year]

proc `$`(x: Activity): string =
  "Activity($1, $2, $3, $4)" % [x.id, x.name, $x.day, $x.start, $x.location]

proc `$`(x: Course): string =
  "Course($1, $2, $3, $4)" % [x.title, $x.year, $x.semester, $x.activities]

proc to_day(x: string): WeekDay =
  ({"Monday": dMon, "Tuesday": dTue, "Wednesday": dWed, "Thursday": dThu, "Friday": dFri}.to_table)[x]

proc parse_activity(course: string, header: XmlNode, data: XmlNode): auto =
  let
    title = header.querySelector("tbody td").inner_text
    id = data.querySelector("td[data-title^=\"Activity\"]").inner_text
    day = data.querySelector("td[data-title^=\"Day\"]").inner_text
    act_time = data.querySelector("td[data-title^=\"Time\"]").inner_text
    times = map(act_time.split({'-'}), proc (value: string): auto = parse(value.strip, "HH:mm"))

  Activity(id: id, name: title, course: course, day: day.to_day, start: times[0], endtime: times[1], location: @[])


proc get_course(course: Course): auto =
  var client = new_http_client()
  let
    url = fmt"http://www.canterbury.ac.nz/courseinfo/GetCourseDetails.aspx?course={course.title}&occurrence={course.year mod 100}S{course.semester}(C)&year={course.year}"
    html = parse_html(new_string_stream(client.get_content(url)))
    activity_table = html.querySelector("table#RepeatTable")

  var
    current_header: XmlNode
    activities = new_seq[Activity]()

  for node in activity_table.items():
    if node.kind != xnElement:
      continue
    elif node.tag() == "headertemplate":
      current_header = node
    elif node.tag() == "tr":
      let activity = parse_activity(course.title, current_header, node)
      activities.add(activity)

  Course(title: course.title, year: course.year, semester: course.semester, activities: activities)

proc group[T; K](arr: seq[T], key: proc (x: T): K {.closure.}): seq[seq[T]] =
  result = new_seq[seq[T]]()
  var last = none(T)
  for el in arr:
    if last.is_none or key(el) != key(last.get()):
      last = some(el)
      result.add(new_seq[T]())
    result[result.len - 1].add(el)

proc get_activities(courses: seq[Course]): auto =
  courses.foldl(concat(a, b.activities), new_seq[Activity]())

proc is_allocated(a: Activity, allocated_activities: TableRef[(string, string), string]): auto =
  let val = allocated_activities.get_or_default((a.course, a.name))
  if val.len > 0:
    val == a.id
  else:
    a.id.strip(chars={'0'}) == "1"

proc activities_on(courses: seq[Course], day: WeekDay): auto =
  let
    activities = courses.get_activities.filter_it(it.day == day)
  activities.sorted do (a: Activity, b: Activity) -> auto: cmp(a.start.to_time, b.start.to_time)

proc activities_allocated(courses: seq[Activity], allocated_activities: TableRef[(string, string), string]): auto =
  courses.filter_it(it.is_allocated(allocated_activities))


proc activities_after(courses: seq[Course], time: DateTime): auto =
  courses.get_activities.filter_it(it.day == time.weekday and it.start.to_time > time.to_time).sorted do (a: Activity, b: Activity) -> auto: cmp(a.start.to_time, b.start.to_time)


proc read_cfg(path: string): auto =
  let cfg = load_config(path)
  var
    tbl = newTable[(string, string), string]()
    courses = new_seq[Course]()
  for section in cfg.keys:
    if section.starts_with("course/"):
      let
        title = section["course/".len..^1]
        semester = cfg.get_section_value(section, "semester").parse_int
        year = cfg.get_section_value(section, "year").parse_int
      courses.add(Course(title: title, semester: semester, year: year, activities: @[]))
    else:
      let
        tokens = section.split("/")
        selected_activity = cfg.get_section_value(section, "activity")
      tbl[(tokens[0], tokens[1].replace("_", " "))] = selected_activity
  (courses: courses, selected_activities: tbl)


proc print_activity(a: Activity) =
  let
    start_string = a.start.format("h:mmtt")
    end_string = a.endtime.format("h:mmtt")
    activity_fmt = fmt" {a.name} @ {start_string} - {end_string}"
  styled_echo(styleDim, a.course, resetStyle, activity_fmt)

proc print_timetable(day: WeekDay, activities: seq[Activity]) =
  styled_echo("Timetable for ", styleDim, $day, resetStyle)
  echo "---"
  for a in activities:
    print_activity(a)


var
  cur = now()
  day_filter = cur.weekday
  next_flag = false
  show_full = true
  config_location = "."

for kind, key, val in getopt():
  case kind
  of cmdArgument: config_location = key
  of cmdLongOption, cmdShortOption:
    case key
    of "on", "o": day_filter = val.to_day
    of "next", "n": next_flag = true
    of "time": show_full = false
  of cmdEnd: assert(false)

let
  cfg = read_cfg(config_location / "config.ini")
  data_location = config_location / "data.json"
var courses: seq[Course]

if file_exists(data_location):
  var data = new_file_stream(data_location, fmRead)
  defer: data.close()
  load(data, courses)
else:
  courses = map(cfg.courses, get_course)
  var outf = new_file_stream(data_location, fmWrite)
  defer: outf.close()
  store(outf, courses)

if next_flag == false:
  let classes = courses.activities_on(day_filter).activities_allocated(cfg.selected_activities)
  print_timetable(day_filter, classes)
else:
  let next_classes = courses.activities_after(cur).activities_allocated(cfg.selected_activities)
  if next_classes.len == 0:
    echo "-"
  elif show_full:
    let next_class = next_classes[0]
    print_activity(next_class)
  else:
    let
      next_class = next_classes[0]
      interval = next_class.start.to_time.to_time_interval - cur.to_time.to_time_interval
      seconds = interval.hours * 3600 + interval.minutes * 60
      hours = seconds div 3600
      minutes = (seconds - hours * 3600) div 60
      start_str = ($minutes).align(2, '0')
    echo fmt"{hours}:{start_str}"
