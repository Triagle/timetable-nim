import
  times, parsecfg, algorithm, os, sequtils, tables, strutils, marshal, httpclient,
  options, xmltree, htmlparser, streams, strformat, terminal
import nimquery

type
  Location = ref object
    name*: string
    year*: BiggestInt
    valid_dates*: seq[DateTime]

  Day = enum
    Monday, Tuesday, Wednesday, Thursday, Friday

  Activity = ref object
    id*: string
    course*: string
    name*: string
    day*: Day
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

proc `$`(x: Day): string =
  ["Monday",  "Tuesday",  "Wednesday", "Thursday", "Friday"][ord(x)]
proc to_day(x: string): Day =
  ({"Monday": Monday, "Tuesday": Tuesday, "Wednesday": Wednesday, "Thursday": Thursday, "Friday": Friday}.to_table)[x]

# proc to_day(x: int): Day =
#   [Monday,  Tuesday,  Wednesday, Thursday, Friday][x]

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

proc is_allocated(a: Activity, allocated_activities: TableRef[(string, string), string]): auto =
  allocated_activities.get_or_default((a.course, a.name)) == a.id or a.id.strip(chars={'0'}) == "1"

proc courses_on(courses: seq[Course], day: Day): auto =
  let
    activities = courses.foldl(concat(a, b.activities), new_seq[Activity]()).filter_it(it.day == day)
  activities.sorted do (a: Activity, b: Activity) -> auto: cmp(a.start.to_time, b.start.to_time)

proc courses_allocated(courses: seq[Activity], allocated_activities: TableRef[(string, string), string]): auto =
  courses.filter_it(it.is_allocated(allocated_activities))


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
    elif section.starts_with("activity/"):
      let
        activity_name = section["activity/".len..^1].replace("_", " ")
        course = cfg.get_section_value(section, "course")
        selected_activity = cfg.get_section_value(section, "activity")
      tbl[(course, activity_name)] = selected_activity
  (courses: courses, selected_activities: tbl)


proc print_courses(day: Day, activities: seq[Activity]) =
  styled_echo("Timetable for ", styleDim, $day, resetStyle)
  echo "---"
  for a in activities:
    let
      start_string = a.start.format("h:mmtt")
      end_string = a.endtime.format("h:mmtt")
      activity_fmt = fmt" {a.name} @ {start_string} - {end_string}"
    styled_echo(styleDim, a.course, resetStyle, activity_fmt)

let cfg = read_cfg("./test.cfg")
print_courses(Friday, map(cfg.courses, get_course).courses_on(Friday).courses_allocated(cfg.selected_activities))
