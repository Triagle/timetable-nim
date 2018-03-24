import
  times, parsecfg, algorithm, os, sequtils, tables, strutils, marshal, httpclient,
  options, xmltree, htmlparser, streams, strformat, terminal, parseopt, ospaths
import nimquery

type
  Interval[A] = tuple[lower: Option[A], upper: Option[A], lower_closed: bool, upper_closed: bool]

  Location = ref object
    name*: string
    weeks*: seq[Interval[Time]]

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

proc satisfied_by[A](interval: Interval[A], member: A): bool =
  let
    satisfies_upper = interval.upper.map(proc (v: A): bool =
                                             if interval.upper_closed: member <= v else: member < v)
    satisfies_lower = interval.lower.map(proc (v: A): bool =
                                             if interval.lower_closed: member >= v else: member > v)
  if interval.lower.is_none:
    satisfies_upper.get(false)
  elif interval.upper.is_none:
    satisfies_lower.get(false)
  else:
    satisfies_lower.get and satisfies_upper.get

proc to_day(x: string): WeekDay =
  ({"Monday": dMon, "Tuesday": dTue, "Wednesday": dWed, "Thursday": dThu, "Friday": dFri, "Saturday": dSat, "Sunday": dSun}.to_table)[x]

proc maybe_get[T](data: openArray[T], index: int): Option[T] =
  if index < 0 or index >= data.len:
    none(T)
  else:
    some(data[index])

proc parse_datestring(datestring: string): DateTime =
  let
    tokens = datestring.split("/")

  result = now()
  result.month = Month(tokens[1].parse_int)
  result.monthday = tokens[0].parse_int


proc parse_locations(data: XmlNode): auto =
  var
    cur_location: Option[string]
    weeks = new_seq[Interval[Time]]()

  result = new_seq[Location]()
  for child in data.items:
    if child.kind == xnText and child.inner_text.strip.len > 0:
      let date_intervals = child.inner_text.strip(chars={'(', ')'}).split(", ").map_it(it.strip.split("-"))
      for tokens in date_intervals:
        let
          lower_bound = tokens.maybe_get(0).map(proc (d: string): auto = d.parse_datestring.to_time)
          upper_bound = if tokens.maybe_get(1).is_none: lower_bound else: tokens.maybe_get(1).map(proc (d: string): auto = d.parse_datestring.to_time)
        weeks.add((lower: lower_bound,
                  upper: upper_bound,
                  lower_closed: true,
                  upper_closed: true))
    elif child.kind == xnElement and child.tag == "a":
      if cur_location.is_some:
        result.add(Location(name: cur_location.get, weeks: weeks))
        weeks = new_seq[Interval[Time]]()
        cur_location = none(string)
      cur_location = some(child.inner_text)
  if cur_location.is_some:
    result.add(Location(name: cur_location.get, weeks: weeks))


proc `$`(l: Location): auto =
  fmt"Location({l.name}, {l.weeks})"

proc parse_activity(course: string, header: XmlNode, data: XmlNode): auto =
  let
    title = header.querySelector("tbody td").inner_text
    id = data.querySelector("td[data-title^=\"Activity\"]").inner_text
    day = data.querySelector("td[data-title^=\"Day\"]").inner_text
    act_time = data.querySelector("td[data-title^=\"Time\"]").inner_text
    locations = data.querySelector("td[data-title^=\"Location\"]").parse_locations
    times = map(act_time.split({'-'}), proc (value: string): auto = parse(value.strip, "HH:mm"))
  Activity(id: id, name: title, course: course, day: day.to_day, start: times[0], endtime: times[1], location: locations)


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


proc print_activity(date: DateTime, a: Activity) =
  let
    start_string = a.start.format("h:mmtt")
    end_string = a.endtime.format("h:mmtt")
    locations = a.location.filter_it(it.weeks.len == 0 or any(it.weeks, proc (i: Interval[Time]): bool = i.satisfied_by(date.to_time)))
    location_string = locations.map_it(it.name).join(",")
    activity_fmt = fmt" {a.name} :: {start_string} - {end_string} @ {location_string}"

  styled_echo(styleDim, a.course, resetStyle, activity_fmt)

proc print_timetable(date: DateTime, activities: seq[Activity]) =
  styled_echo("Timetable for ", styleDim, $date.weekday, resetStyle)
  echo "---"
  for a in activities:
    print_activity(date, a)


var
  cur = now()
  next_flag = false
  show_full = true
  config_location = "."

for kind, key, val in getopt():
  case kind
  of cmdArgument: config_location = key
  of cmdLongOption, cmdShortOption:
    case key
    of "on", "o": cur = (cur.to_time - (ord(cur.weekday) - ord(val.to_day)).days).local
    of "next", "n": next_flag = true
    of "time": show_full = false
  of cmdEnd: assert(false)

let
  cfg = read_cfg(config_location / "config")
  data_location = config_location / "data.json"
var courses: seq[Course]
if file_exists(data_location):
  var data = new_file_stream(data_location, fmRead)
  load(data, courses)
  defer: data.close()
else:
  courses = map(cfg.courses, get_course)
  var outf = new_file_stream(data_location, fmWrite)
  store(outf, courses)
  defer: outf.close()

if next_flag == false:
  let classes = courses.activities_on(cur.weekday).activities_allocated(cfg.selected_activities)
  print_timetable(cur, classes)
else:
  let cur = now()
  let next_classes = courses.activities_after(cur).activities_allocated(cfg.selected_activities)
  if next_classes.len == 0:
    echo "-"
  elif show_full:
    let next_class = next_classes[0]
    print_activity(cur, next_class)
  else:
    let
      next_class = next_classes[0]
      interval = next_class.start.to_time.to_time_interval - cur.to_time.to_time_interval
      seconds = interval.hours * 3600 + interval.minutes * 60
      hours = seconds div 3600
      minutes = (seconds - hours * 3600) div 60
      start_str = ($minutes).align(2, '0')
    echo fmt"{hours}:{start_str}"
