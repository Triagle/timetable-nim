import sequtils
import strutils
import system

proc columns[T](data: seq[seq[T]]): seq[seq[T]] =
  var columns: seq[seq[T]] = @[]
  for i in 0..<data[0].len:
    columns.add(map(data, proc(r: seq[T]): T = r[i]))
  return columns

proc height(text: string): int =
  len(text.split_lines())

proc render_row(row: seq[string], widths: seq[int]): auto =
  let height = max(map(row, height))
  var buffer = newSeqWith(height, newSeq[string]())
  for idx, cell in row:
    let
      cell_lines = cell.split_lines
      height_pad = height - cell_lines.len
      width = widths[idx]

    for j in 0..<cell_lines.len:
      buffer[j].add("| $1 " % [align_left(cell_lines[j], width)])

    for j in 0..<height_pad:
      buffer[cell_lines.len + j].add("| $1 " % [align_left("", width)])

  # Buffer Separator
  let last_row = buffer[buffer.len - 1]
  var seperator = ""

  for cell in last_row:
    let length = cell.len
    seperator.add("+$1" % "-".repeat(length - 1))

  seperator.add("+")
  buffer[buffer.len - 1].add("|")
  (sep: seperator, row: buffer.map_it(it.join()).join("|\n"))

proc pop[T](l: var seq[T]): T =
  result = l[l.len - 1]
  l.delete(l.len - 1)

proc draw_table(data: seq[seq[string]]): seq[string] =
  let
    widths = map(data.columns, proc(c: seq[string]): int = max(map_it(c, len(it))))
  var table = newSeq[string]()

  for row in data:
    let (sep, row) = render_row(row, widths)
    table.add(row)
    table.add(sep)

  discard table.pop()
  table
