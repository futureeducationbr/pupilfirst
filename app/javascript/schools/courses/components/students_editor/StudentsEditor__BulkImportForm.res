let str = React.string

open StudentsEditor__Types

let t = I18n.t(~scope="components.StudentsEditor__BulkImportForm")

module CSVData = {
  type t = StudentCSVData.t
}

module CSVReader = CSVReader.Make(CSVData)

type fileInvalid =
  | InvalidCSVFile
  | EmptyFile
  | InvalidTemplate
  | ExceededEntries
  | InvalidData(array<CSVDataError.t>)

type state = {
  fileInfo: option<CSVReader.fileInfo>,
  saving: bool,
  csvData: array<StudentCSVData.t>,
  fileInvalid: option<fileInvalid>,
}

let initialState = {
  fileInfo: None,
  saving: false,
  csvData: [],
  fileInvalid: None,
}

let validTemplate = csvData => {
  let firstRow = Js.Array.unsafe_get(csvData, 0)
  StudentCSVData.name(firstRow)->Belt.Option.isSome
}

let validateFile = (csvData, fileInfo) => {
  CSVReader.fileSize(fileInfo) > 100000 || CSVReader.fileType(fileInfo) != "text/csv"
    ? Some(InvalidCSVFile)
    : csvData |> ArrayUtils.isEmpty
    ? Some(EmptyFile)
    : !validTemplate(csvData)
    ? Some(InvalidTemplate)
    : Array.length(csvData) > 1000
    ? Some(ExceededEntries)
    : {
        let dataErrors = CSVDataError.parseError(csvData)
        dataErrors |> ArrayUtils.isNotEmpty ? Some(InvalidData(dataErrors)) : None
      }
}

type action =
  | UpdateFileInvalid(option<fileInvalid>)
  | LoadCSVData(array<StudentCSVData.t>, CSVReader.fileInfo)
  | ClearCSVData
  | BeginSaving
  | EndSaving
  | FailSaving

let fileInputText = (~fileInfo: option<CSVReader.fileInfo>) =>
  fileInfo->Belt.Option.mapWithDefault(t("csv_file_input_placeholder"), info => info.name)

let reducer = (state, action) =>
  switch action {
  | UpdateFileInvalid(fileInvalid) => {...state, fileInvalid: fileInvalid}
  | ClearCSVData => {...state, fileInfo: None, fileInvalid: None, csvData: []}
  | BeginSaving => {...state, saving: true}
  | FailSaving => {...state, saving: false}
  | EndSaving => initialState
  | LoadCSVData(csvData, fileInfo) => {
      ...state,
      csvData: csvData,
      fileInfo: Some(fileInfo),
      fileInvalid: validateFile(csvData, fileInfo),
    }
  }

let saveDisabled = state =>
  state.fileInfo->Belt.Option.isNone || state.fileInvalid->Belt.Option.isSome || state.saving

let submitForm = (courseId, send, event) => {
  ReactEvent.Form.preventDefault(event)
  send(BeginSaving)

  let formData =
    ReactEvent.Form.target(event)->DomUtils.EventTarget.unsafeToElement->DomUtils.FormData.create

  let url = "/school/courses/" ++ courseId ++ "/bulk_import_students"

  Api.sendFormData(
    url,
    formData,
    json => {
      Json.Decode.field("success", Json.Decode.bool, json)
        ? Notification.success(t("done_exclamation"), t("success_notification"))
        : ()
      send(EndSaving)
    },
    () => send(FailSaving),
  )
}

let tableHeader = {
  <thead>
    <tr className="bg-gray-200">
      <th className="text-left text-xs"> {"no" |> str} </th>
      <th className="text-left text-xs"> {"name" |> str} </th>
      <th className="text-left text-xs"> {"email" |> str} </th>
      <th className="text-left text-xs"> {"title" |> str} </th>
      <th className="text-left text-xs"> {"team_name" |> str} </th>
      <th className="text-left text-xs"> {"tags" |> str} </th>
      <th className="text-left text-xs"> {"affiliation" |> str} </th>
    </tr>
  </thead>
}

let csvDataTable = (csvData, fileInvalid) => {
  ReactUtils.nullIf(
    <table className="table-auto mt-5 border w-full overflow-x-scroll">
      {tableHeader}
      <tbody>
        {csvData
        |> Array.mapi((index, studentData) =>
          <tr key={string_of_int(index)}>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {string_of_int(index + 2) |> str}
            </td>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {StudentCSVData.name(studentData)->Belt.Option.getWithDefault("") |> str}
            </td>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {StudentCSVData.email(studentData)->Belt.Option.getWithDefault("") |> str}
            </td>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {StudentCSVData.title(studentData)->Belt.Option.getWithDefault("") |> str}
            </td>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {StudentCSVData.teamName(studentData)->Belt.Option.getWithDefault("") |> str}
            </td>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {StudentCSVData.tags(studentData)->Belt.Option.getWithDefault("") |> str}
            </td>
            <td className="border border-gray-400 truncate text-xs px-2 py-1">
              {StudentCSVData.affiliation(studentData)->Belt.Option.getWithDefault("") |> str}
            </td>
          </tr>
        )
        |> React.array}
      </tbody>
    </table>,
    fileInvalid->Belt.Option.isSome,
  )
}

let clearFile = send => {
  open Webapi.Dom

  switch document |> Document.getElementById("csv-file-input") {
  | Some(e) => HtmlInputElement.setValue(DomUtils.Element.unsafeToHtmlInputElement(e), "")
  | None => ()
  }

  send(ClearCSVData)
}

let errorsTable = (csvData, errors) => {
  <table className="table-auto mt-5 border w-full overflow-x-scroll">
    {tableHeader} <tbody> {errors |> Array.mapi((index, error) => {
        let rowNumber = CSVDataError.rowNumber(error)
        let studentData = Js.Array2.unsafe_get(csvData, rowNumber - 2)
        <tr key={string_of_int(index)}>
          <td className="border border-gray-400 truncate text-xs px-2 py-1">
            {rowNumber |> string_of_int |> str}
          </td>
          <td
            className={"border border-gray-400 truncate text-xs px-2 py-1 " ++ (
              CSVDataError.hasNameError(error) ? "bg-red-300" : ""
            )}>
            {StudentCSVData.name(studentData)->Belt.Option.getWithDefault("") |> str}
          </td>
          <td
            className={"border border-gray-400 truncate text-xs px-2 py-1 " ++ (
              CSVDataError.hasEmailError(error) ? "bg-red-300" : ""
            )}>
            {StudentCSVData.email(studentData)->Belt.Option.getWithDefault("") |> str}
          </td>
          <td
            className={"border border-gray-400 truncate text-xs px-2 py-1 " ++ (
              CSVDataError.hasTitleError(error) ? "bg-red-300" : ""
            )}>
            {StudentCSVData.title(studentData)->Belt.Option.getWithDefault("") |> str}
          </td>
          <td
            className={"border border-gray-400 truncate text-xs px-2 py-1 " ++ (
              CSVDataError.hasTeamNameError(error) ? "bg-red-300" : ""
            )}>
            {StudentCSVData.teamName(studentData)->Belt.Option.getWithDefault("") |> str}
          </td>
          <td
            className={"border border-gray-400 truncate text-xs px-2 py-1 " ++ (
              CSVDataError.hasTagsError(error) ? "bg-red-300" : ""
            )}>
            {StudentCSVData.tags(studentData)->Belt.Option.getWithDefault("") |> str}
          </td>
          <td
            className={"border border-gray-400 truncate text-xs px-2 py-1 " ++ (
              CSVDataError.hasAffiliationError(error) ? "bg-red-300" : ""
            )}>
            {StudentCSVData.affiliation(studentData)->Belt.Option.getWithDefault("") |> str}
          </td>
        </tr>
      }) |> React.array} </tbody>
  </table>
}

let errorTabulation = (csvData, fileInvalid) => {
  switch fileInvalid {
  | None => React.null
  | Some(fileInvalid) =>
    switch fileInvalid {
    | InvalidData(errors) =>
      <div>
        {errors->Array.length > 10
          ? {
              <div>
                {errorsTable(csvData, Js.Array.slice(~start=0, ~end_=10, errors))}
                <div className="text-red-700 text-sm mt-5">
                  {"There are even more errors. Fix the errors in the following rows and upload again: " |> str}
                  <textArea readOnly=true className="w-full bg-gray-200 p-1">
                    {Array.map(
                      error => CSVDataError.rowNumber(error),
                      Js.Array2.sliceFrom(errors, 10),
                    )->Js.Array2.joinWith(",") |> str}
                  </textArea>
                </div>
              </div>
            }
          : errorsTable(csvData, errors)}
        <div className="text-red-700 text-sm mt-5">
          <div className="text-sm pb-2">
            {"Here is a summary of the errors in the sheet: " |> str}
          </div>
          <ul className="list-disc list-inside">
            {errors
            |> Array.map(error => CSVDataError.errors(error))
            |> ArrayUtils.flattenV2
            |> ArrayUtils.distinct
            |> Array.map(error =>
              <li>
                {str(
                  switch error {
                  | CSVDataError.Name => "Name column can't be blank"
                  | Title => "Title has to be less than 250 characters"
                  | TeamName => "Team name has to be less than 50 characters"
                  | Email => "Email has to be valid and can't be blank"
                  | Affiliation => "Affiliation has to be less than 250 characters"
                  | Tags => "Tags has to be less than 5 in numbers"
                  },
                )}
              </li>
            )
            |> React.array}
          </ul>
        </div>
      </div>
    | _ => React.null
    }
  }
}

@react.component
let make = (~courseId) => {
  let (state, send) = React.useReducer(reducer, initialState)
  <form onSubmit={submitForm(courseId, send)}>
    <input name="authenticity_token" type_="hidden" value={AuthenticityToken.fromHead()} />
    <div className="mx-auto bg-white">
      <div className="max-w-2xl p-6 mx-auto">
        <h5 className="uppercase text-center border-b border-gray-400 pb-2 mb-4">
          {t("drawer_heading")->str}
        </h5>
        <DisablingCover disabled={state.saving} message="Processing...">
          <div className="mt-5">
            <div>
              <label className="tracking-wide text-xs font-semibold" htmlFor="csv-file-input">
                {t("csv_file_input_label")->str}
              </label>
              <HelpIcon
                className="ml-2"
                link="https://docs.pupilfirst.com/#/certificates?id=uploading-a-new-certificate">
                {str(
                  "This file will be used to import students in bulk. Check the sample file for the required format.",
                )}
              </HelpIcon>
            </div>
            <CSVReader
              label=""
              inputId="csv-file-input"
              inputName="csv"
              cssClass="hidden"
              parserOptions={CSVReader.parserOptions(~header=true, ~skipEmptyLines="true", ())}
              onFileLoaded={(x, y) => {
                send(LoadCSVData(x, y))
              }}
              onError={_ => send(UpdateFileInvalid(Some(InvalidCSVFile)))}
            />
            <label
              onClick={_event => clearFile(send)}
              className="file-input-label my-2"
              htmlFor="csv-file-input">
              <i className="fas fa-upload mr-2 text-gray-600 text-lg" />
              <span className="truncate"> {fileInputText(~fileInfo=state.fileInfo)->str} </span>
            </label>
            {ReactUtils.nullIf(
              csvDataTable(state.csvData, state.fileInvalid),
              ArrayUtils.isEmpty(state.csvData),
            )}
            <School__InputGroupError
              message={switch state.fileInvalid {
              | Some(invalidStatus) =>
                switch invalidStatus {
                | InvalidCSVFile => t("csv_file_errors.invalid")
                | EmptyFile => t("csv_file_errors.empty")
                | InvalidTemplate => t("csv_file_errors.invalid_template")
                | ExceededEntries => t("csv_file_errors.exceeded_entries")
                | InvalidData(_) => t("csv_file_errors.invalid_data")
                }
              | None => ""
              }}
              active={state.fileInvalid->Belt.Option.isSome}
            />
            {errorTabulation(state.csvData, state.fileInvalid)}
          </div>
        </DisablingCover>
      </div>
      <div className="max-w-2xl p-6 mx-auto">
        <button disabled={saveDisabled(state)} className="w-auto btn btn-large btn-primary">
          {t("import_button_text")->str}
        </button>
      </div>
    </div>
  </form>
}