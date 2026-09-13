# Import equipment

Open **Assets → More actions → Import equipment** as a company owner or another
member with equipment-management permission.

1. Choose an XLSX, CSV, TSV or TXT file, or paste rows copied from a spreadsheet.
2. For Excel, select the worksheet. Select the header row, or **No header** for
   a plain list of equipment names. CSV files offer comma, semicolon and tab
   separators when automatic detection needs correcting.
3. Match your column headings to the equipment fields. Only mapped columns are
   imported. Choose a default equipment type for blank type cells, and map any
   unfamiliar type names to a type offered by Vortice.
4. Check the meter unit. Hours, kilometres and miles are separate units; import
   does not convert between them. Keep serial/VIN cells as text in the source
   spreadsheet to preserve leading zeroes. Paste formulas as values.
5. Preview the import. Review equipment details, component readings and service
   baselines. Correct the mapping or exclude rows with errors, then confirm.

The import adds new equipment. It never updates existing fleet records.
Matching names or serial numbers in the same fleet require review. Repeated
rows can describe separate components or separate service plans on one component
when their equipment and component details agree. Identical duplicate rows must
be excluded explicitly.

Supported source formats:

| Source | Supported details |
| --- | --- |
| Excel `.xlsx` | Multiple worksheets, selectable header row, text and numeric cells, native Excel dates |
| `.csv` | Comma, semicolon or tab separators; quoted fields and line breaks |
| `.tsv` | Tab-separated spreadsheet exports |
| `.txt` | Delimited tables or one equipment name per line using **No header** |
| Pasted text | Copied spreadsheet tables or plain equipment-name lists |

Text files support UTF-8 (with or without a BOM) and UTF-16 little/big endian
with a BOM. For older Windows encodings, save the export as **CSV UTF-8** first.
Choose the decimal-comma setting for readings such as `125,5`; omit thousands
separators. Formula cells in mapped fields must be replaced with values.

Legacy `.xls`, macro-enabled `.xlsm`, `.ods`, `.numbers`, PDF, images, Word and
JSON files are not accepted directly. Export an `.xlsx` or UTF-8 CSV, or copy
the table into the paste field. A Google Sheets link is not an import source;
download its Excel/CSV export or paste its cells.

An opening equipment reading creates an **Equipment meter**. A named component
can have its own reading and unit. Service-plan columns refer to the named
component, or to the equipment meter when no component is named. A meter-based
plan needs both an opening reading and a last-service reading. A monthly plan
needs its last-service date. Choose ISO, month/day/year or day/month/year for
text dates; Excel date cells preserve their calendar date.

One published checklist can be selected for all imported service plans. Vortice
checks its company and equipment-type compatibility before saving. Plan imports
require the fleet's maintenance-planning feature and the member's planning
permission. These values initialize recurring plans; they are not signed service
completion records and do not book calendar appointments.

Use files under 5 MB and tables with at most 1,000 data rows and 100 columns.
Each saved batch supports at most 500 equipment records and 1,000 components.
Complex or very large Excel workbooks should be exported as smaller CSV files.

If a save loses its connection, **Retry same import** resumes the exact batch.
The pending import is retained for that signed-in account, and the server returns
the original receipt when it already succeeded. A confirmed validation rejection
returns to column mapping for correction. An interrupted, unsaved mapping can be
recreated from the source file; it has not changed the fleet.

Excel and Google Sheets exports and tables from other fleet systems use this
same mapping flow. PDF/photos and older binary XLS files need a supported table
export first. This importer does not establish an ongoing live connection to
the source system or import its attachments, invoices, users or work history.
