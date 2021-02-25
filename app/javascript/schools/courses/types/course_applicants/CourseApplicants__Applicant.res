type t = {
  id: string,
  name: string,
  email: string,
  tags: array<string>,
}

let name = t => t.name

let tags = t => t.tags

let id = t => t.id

let email = t => t.email

let make = (~id, ~name, ~tags, ~email) => {
  id: id,
  name: name,
  tags: tags,
  email: email,
}

let makeFromJS = applicantDetails =>
  make(
    ~id=applicantDetails["id"],
    ~name=applicantDetails["name"],
    ~tags=applicantDetails["tags"],
    ~email=applicantDetails["email"],
  )
