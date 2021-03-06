let str = React.string
let t = I18n.t(~scope="components.UserEdit")

type state = {
  name: string,
  about: string,
  avatarUrl: option<string>,
  currentPassword: string,
  newPassword: string,
  confirmPassword: string,
  dailyDigest: bool,
  emailForAccountDeletion: string,
  showDeleteAccountForm: bool,
  hasCurrentPassword: bool,
  deletingAccount: bool,
  avatarUploadError: option<string>,
  saving: bool,
  dirty: bool,
}

type action =
  | UpdateName(string)
  | UpdateAbout(string)
  | UpdateCurrentPassword(string)
  | UpdateNewPassword(string)
  | UpdateNewPassWordConfirm(string)
  | UpdateEmailForDeletion(string)
  | UpdateDailyDigest(bool)
  | UpdateAvatarUrl(option<string>)
  | ChangeDeleteAccountFormVisibility(bool)
  | SetAvatarUploadError(option<string>)
  | StartSaving
  | ResetSaving
  | FinishSaving(bool)
  | StartDeletingAccount
  | FinishAccountDeletion

let reducer = (state, action) =>
  switch action {
  | UpdateName(name) => {...state, name: name, dirty: true}
  | UpdateAbout(about) => {...state, about: about, dirty: true}
  | UpdateCurrentPassword(currentPassword) => {
      ...state,
      currentPassword: currentPassword,
      dirty: true,
    }
  | UpdateNewPassword(newPassword) => {...state, newPassword: newPassword, dirty: true}
  | UpdateNewPassWordConfirm(confirmPassword) => {
      ...state,
      confirmPassword: confirmPassword,
      dirty: true,
    }
  | UpdateEmailForDeletion(emailForAccountDeletion) => {
      ...state,
      emailForAccountDeletion: emailForAccountDeletion,
    }
  | UpdateDailyDigest(dailyDigest) => {...state, dailyDigest: dailyDigest, dirty: true}
  | StartSaving => {...state, saving: true}
  | ChangeDeleteAccountFormVisibility(showDeleteAccountForm) => {
      ...state,
      showDeleteAccountForm: showDeleteAccountForm,
      emailForAccountDeletion: "",
    }
  | SetAvatarUploadError(avatarUploadError) => {...state, avatarUploadError: avatarUploadError}
  | UpdateAvatarUrl(avatarUrl) => {
      ...state,
      avatarUrl: avatarUrl,
      avatarUploadError: None,
    }
  | FinishSaving(hasCurrentPassword) => {
      ...state,
      saving: false,
      dirty: false,
      currentPassword: "",
      newPassword: "",
      confirmPassword: "",
      hasCurrentPassword: hasCurrentPassword,
    }
  | ResetSaving => {...state, saving: false}
  | StartDeletingAccount => {...state, deletingAccount: true}
  | FinishAccountDeletion => {
      ...state,
      showDeleteAccountForm: false,
      deletingAccount: false,
      emailForAccountDeletion: "",
    }
  }

module UpdateUserQuery = %graphql(
  `
   mutation UpdateUserMutation($name: String!, $about: String, $currentPassword: String, $newPassword: String, $confirmPassword: String, $dailyDigest: Boolean! ) {
     updateUser(name: $name, about: $about, currentPassword: $currentPassword, newPassword: $newPassword, confirmNewPassword: $confirmPassword, dailyDigest: $dailyDigest  ) {
        success
       }
     }
   `
)

module InitiateAccountDeletionQuery = %graphql(
  `
   mutation InitiateAccountDeletionMutation($email: String! ) {
     initiateAccountDeletion(email: $email ) {
        success
       }
     }
   `
)

let uploadAvatar = (send, formData) => {
  open Json.Decode
  Api.sendFormData(
    "/user/upload_avatar",
    formData,
    json => {
      Notification.success("Feito!", "Avatar carregado com sucesso.")
      let avatarUrl = json |> field("avatarUrl", string)
      send(UpdateAvatarUrl(Some(avatarUrl)))
    },
    () => send(SetAvatarUploadError(Some("Failed to upload"))),
  )
}
let submitAvatarForm = (send, formId) => {
  let element = ReactDOMRe._getElementById(formId)

  switch element {
  | Some(element) => DomUtils.FormData.create(element) |> uploadAvatar(send)
  | None => Rollbar.error("Could not find form to upload file for content block: " ++ formId)
  }
}

let handleAvatarInputChange = (send, formId, event) => {
  event |> ReactEvent.Form.preventDefault

  switch ReactEvent.Form.target(event)["files"] {
  | [] => ()
  | files =>
    let file = files[0]

    let maxAllowedFileSize = 30 * 1024 * 1024
    let isInvalidImageFile =
      file["size"] > maxAllowedFileSize ||
        switch file["_type"] {
        | "image/jpeg"
        | "image/gif"
        | "image/png" => false
        | _ => true
        }

    let error = isInvalidImageFile
      ? Some("Please select an image with a size less than 5 MB")
      : None

    switch error {
    | Some(error) => send(SetAvatarUploadError(Some(error)))
    | None => submitAvatarForm(send, formId)
    }
  }
}

let updateUser = (state, send, event) => {
  ReactEvent.Mouse.preventDefault(event)
  send(StartSaving)

  UpdateUserQuery.make(
    ~name=state.name,
    ~about=state.about,
    ~currentPassword=state.currentPassword,
    ~newPassword=state.newPassword,
    ~confirmPassword=state.confirmPassword,
    ~dailyDigest=state.dailyDigest,
    (),
  )
  |> GraphqlQuery.sendQuery
  |> Js.Promise.then_(result => {
    result["updateUser"]["success"]
      ? {
          let hasCurrentPassword = state.newPassword |> String.length > 0
          send(FinishSaving(hasCurrentPassword))
        }
      : send(FinishSaving(state.hasCurrentPassword))
    Js.Promise.resolve()
  })
  |> Js.Promise.catch(_ => {
    send(ResetSaving)
    Js.Promise.resolve()
  })
  |> ignore
  ()
}

let initiateAccountDeletion = (state, send) => {
  send(StartDeletingAccount)

  InitiateAccountDeletionQuery.make(~email=state.emailForAccountDeletion, ())
  |> GraphqlQuery.sendQuery
  |> Js.Promise.then_(result => {
    result["initiateAccountDeletion"]["success"]
      ? send(FinishAccountDeletion)
      : send(FinishAccountDeletion)
    Js.Promise.resolve()
  })
  |> Js.Promise.catch(_ => {
    send(FinishAccountDeletion)
    Js.Promise.resolve()
  })
  |> ignore
  ()
}

let hasInvalidPassword = state =>
  (state.newPassword == "" && state.confirmPassword == "") ||
    (state.newPassword == state.confirmPassword && state.newPassword |> String.length >= 8)
    ? false
    : true

let saveDisabled = state =>
  hasInvalidPassword(state) || (state.name |> String.trim |> String.length == 0 || !state.dirty)

let confirmDeletionWindow = (state, send) =>
  state.showDeleteAccountForm
    ? {
        let body =
          <div ariaLabel="Confirm dialog for account deletion">
            <p className="text-sm text-center sm:text-left text-gray-700">
              {"Tem certeza que deseja deletar sua conta?" |> str}
            </p>
            <div className="mt-3">
              <label htmlFor="email" className="block text-sm font-semibold">
                {"Confirme seu email" |> str}
              </label>
              <input
                type_="email"
                value=state.emailForAccountDeletion
                onChange={event =>
                  send(UpdateEmailForDeletion(ReactEvent.Form.target(event)["value"]))}
                id="email"
                autoComplete="off"
                className="appearance-none block text-sm w-full shadow-sm border border-gray-400 rounded px-4 py-2 my-2 leading-relaxed focus:outline-none focus:border-gray-500"
                placeholder="Digite seu email"
              />
            </div>
          </div>

        <ConfirmWindow
          title="Apagar minha conta"
          body
          confirmButtonText="Apagando sua conta"
          cancelButtonText="Cancelar"
          onConfirm={() => initiateAccountDeletion(state, send)}
          onCancel={() => send(ChangeDeleteAccountFormVisibility(false))}
          disableConfirm=state.deletingAccount
          alertType=#Critical
        />
      }
    : React.null

@react.component
let make = (
  ~name,
  ~hasCurrentPassword,
  ~about,
  ~avatarUrl,
  ~dailyDigest,
  ~isSchoolAdmin,
  ~hasValidDeleteAccountToken,
) => {
  let initialState = {
    name: name,
    about: about,
    avatarUrl: avatarUrl,
    dailyDigest: dailyDigest |> OptionUtils.mapWithDefault(d => d, false),
    saving: false,
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
    emailForAccountDeletion: "",
    showDeleteAccountForm: false,
    hasCurrentPassword: hasCurrentPassword,
    deletingAccount: false,
    avatarUploadError: None,
    dirty: false,
  }

  let (state, send) = React.useReducer(reducer, initialState)
  <div className="container mx-auto px-3 py-8 max-w-5xl">
    {confirmDeletionWindow(state, send)}
    <div className="bg-white shadow sm:rounded-lg">
      <div className="px-4 py-5 sm:p-6">
        <div className="flex flex-col md:flex-row">
          <div className="w-full md:w-1/3 pr-4">
            <h3 className="text-lg font-semibold"> {"Atualizar Perfil" |> str} </h3>
            <p className="mt-1 text-sm text-gray-700">
              {"Mantenha os seus dados sempre atualizados." |> str}
            </p>
          </div>
          <div className="mt-5 md:mt-0 w-full md:w-2/3">
            <div className="">
              <div className="">
                <label htmlFor="user_name" className="block text-sm font-semibold">
                  {"Nome" |> str}
                </label>
              </div>
            </div>
            <input
              id="user_name"
              name="name"
              value=state.name
              onChange={event => send(UpdateName(ReactEvent.Form.target(event)["value"]))}
              className="appearance-none mb-2 block text-sm w-full shadow-sm border border-gray-400 rounded px-4 py-2 my-2 leading-relaxed focus:outline-none focus:border-gray-500"
              placeholder="Informe o seu nome"
            />
            <School__InputGroupError
              message="Name can't be blank" active={state.name |> String.trim |> String.length < 2}
            />
            <div className="mt-6">
              <label htmlFor="about" className="block text-sm font-semibold">
                {"Sobre" |> str}
              </label>
              <div>
                <textarea
                  id="about"
                  value=state.about
                  rows=3
                  onChange={event => send(UpdateAbout(ReactEvent.Form.target(event)["value"]))}
                  className="appearance-none block text-sm w-full shadow-sm border border-gray-400 rounded px-4 py-2 my-2 leading-relaxed focus:outline-none focus:border-gray-500"
                  placeholder="Descreva sobre algo"
                />
              </div>
            </div>
            <div className="mt-6">
              <form id="user-avatar-uploader">
                <input
                  name="authenticity_token" type_="hidden" value={AuthenticityToken.fromHead()}
                />
                <label className="block text-sm font-semibold"> {"Foto" |> str} </label>
                <div className="mt-2 flex items-center">
                  <span
                    className="inline-block h-14 w-14 rounded-full overflow-hidden bg-gray-200 border-2 boder-gray-400">
                    {switch state.avatarUrl {
                    | Some(url) => <img src=url />
                    | None => <Avatar name />
                    }}
                  </span>
                  <span className="ml-5 inline-flex">
                    <input
                      className="form-input__file-sr-only"
                      name="user[avatar]"
                      type_="file"
                      ariaLabel="user-edit__avatar-input"
                      onChange={handleAvatarInputChange(send, "user-avatar-uploader")}
                      id="user-edit__avatar-input"
                      required=false
                      multiple=false
                    />
                    <label
                      htmlFor="user-edit__avatar-input"
                      ariaHidden=true
                      className="form-input__file-label rounded-md shadow-sm py-2 px-3 border border-gray-400 rounded-md text-sm font-semibold hover:text-gray-800 active:bg-gray-100 active:text-gray-800">
                      {"Mudar foto" |> str}
                    </label>
                  </span>
                  {switch state.avatarUploadError {
                  | Some(error) => <School__InputGroupError message=error active=true />
                  | None => React.null
                  }}
                </div>
              </form>
            </div>
          </div>
        </div>
        <div className="flex flex-col md:flex-row mt-10 md:mt-12">
          <div className="w-full md:w-1/3 pr-4">
            <h3 className="text-lg font-semibold"> {t("security_title") |> str} </h3>
            <p className="mt-1 text-sm text-gray-700">
              {"Atualize suas credenciais de login." |> str}
            </p>
          </div>
          <div className="mt-5 md:mt-0 w-full md:w-2/3">
            <p className="font-semibold">
              {(
                state.hasCurrentPassword
                  ? "Mudar a sua senha atual"
                  : "Defina a nova senha"
              ) |> str}
            </p>
            {state.hasCurrentPassword
              ? <div className="mt-6">
                  <label htmlFor="current_password" className="block text-sm font-semibold">
                    {"Senha Atual" |> str}
                  </label>
                  <input
                    value=state.currentPassword
                    type_="password"
                    autoComplete="off"
                    onChange={event =>
                      send(UpdateCurrentPassword(ReactEvent.Form.target(event)["value"]))}
                    id="current_password"
                    className="appearance-none block text-sm w-full shadow-sm border border-gray-400 rounded px-4 py-2 my-2 leading-relaxed focus:outline-none focus:border-gray-500"
                    placeholder="Digite a senha atual"
                  />
                </div>
              : React.null}
            <div className="mt-6">
              <label htmlFor="new_password" className="block text-sm font-semibold">
                {"Nova Senha" |> str}
              </label>
              <input
                autoComplete="off"
                type_="password"
                id="new_password"
                value=state.newPassword
                onChange={event => send(UpdateNewPassword(ReactEvent.Form.target(event)["value"]))}
                className="appearance-none block text-sm w-full shadow-sm border border-gray-400 rounded px-4 py-2 my-2 leading-relaxed focus:outline-none focus:border-gray-500"
                placeholder="Digite uma nova senha"
              />
            </div>
            <div className="mt-6">
              <label
                autoComplete="off"
                htmlFor="confirm_password"
                className="block text-sm font-semibold">
                {"Confirme a Senha" |> str}
              </label>
              <input
                autoComplete="off"
                type_="password"
                id="confirm_password"
                value=state.confirmPassword
                onChange={event =>
                  send(UpdateNewPassWordConfirm(ReactEvent.Form.target(event)["value"]))}
                className="appearance-none block text-sm w-full shadow-sm border border-gray-400 rounded px-4 py-2 my-2 leading-relaxed focus:outline-none focus:border-gray-500"
                placeholder="Confirme a nova senha"
              />
              <School__InputGroupError
                message="A nova senha e a confirmacao devem corresponder e ter pelo menos 8 caracteres"
                active={hasInvalidPassword(state)}
              />
            </div>
          </div>
        </div>
        <div className="flex flex-col md:flex-row mt-10 md:mt-12">
          <div className="w-full md:w-1/3 pr-4">
            <h3 className="text-lg font-semibold"> {t("notification_title") |> str} </h3>
            <p className="mt-1 text-sm text-gray-700">
              {t("notification_description") |> str}
            </p>
          </div>
          <div className="mt-5 md:mt-0 w-full md:w-2/3">
            <p className="font-semibold"> {"Resumo das Comunidades" |> str} </p>
            <p className="text-sm text-gray-700">
              {t("notification_resume") |> str}
            </p>
            <div className="mt-6">
              <div className="flex items-center">
                <Radio
                  id="daily_mail_enable"
                  label="Envie-me um email diario"
                  onChange={event =>
                    send(UpdateDailyDigest(ReactEvent.Form.target(event)["checked"]))}
                  checked=state.dailyDigest
                />
              </div>
              <div className="mt-4 flex items-center">
                <Radio
                  id="daily_mail_disable"
                  label="Parar de receber"
                  onChange={event =>
                    send(UpdateDailyDigest(!ReactEvent.Form.target(event)["checked"]))}
                  checked={!state.dailyDigest}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
      <div className="bg-gray-100 px-4 py-5 sm:p-6 flex rounded-b-lg justify-end">
        <button
          disabled={saveDisabled(state)}
          onClick={updateUser(state, send)}
          className="btn btn-primary">
          {"Salvar Perfil" |> str}
        </button>
      </div>
    </div>
    <div className="bg-white shadow sm:rounded-lg mt-10">
      <div className="px-4 py-5 sm:p-6">
        <div className="flex flex-col md:flex-row">
          <div className="w-full md:w-1/3 pr-4">
            <h3 className="text-lg font-semibold"> {"Conta" |> str} </h3>
            <p className="mt-1 text-sm text-gray-700">
              {"Gerencie a sua conta" |> str}
            </p>
          </div>
          <div className="mt-5 md:mt-0 w-full md:w-2/3">
            <p className="font-semibold text-red-700"> {"Apagar minha conta e cancelar minha assinatura" |> str} </p>
            <p className="text-sm text-gray-700 mt-1">
              {t("close_account_description") |> str}
            </p>
            <div className="mt-4">
              {isSchoolAdmin || hasValidDeleteAccountToken
                ? <div className="bg-orange-100 border-l-4 border-orange-400 p-4">
                    <div className="flex">
                      <FaIcon classes="fas fa-exclamation-triangle text-orange-400" />
                      <div className="ml-3">
                        <p className="text-sm text-orange-900">
                          {(
                            isSchoolAdmin
                              ? "You are currently an admin of this school. Please delete your admin access to enable account deletion."
                              : "You have already initiated account deletion. Please check your inbox for further steps to delete your account."
                          ) |> str}
                        </p>
                      </div>
                    </div>
                  </div>
                : <button
                    onClick={_ => send(ChangeDeleteAccountFormVisibility(true))}
                    className="py-2 px-3 border border-red-500 text-red-600 rounded text-xs font-semibold hover:bg-red-600 hover:text-white focus:outline-none active:bg-red-700 active:text-white">
                    {"Apagar minha conta" |> str}
                  </button>}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
}
