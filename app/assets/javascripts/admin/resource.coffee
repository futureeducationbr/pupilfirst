$(document).on 'page:change', ->
  resourceTagList = $('#resource_tag_list')

  if resourceTagList.length
    resourceTagList.select2
      width: '80%',
      placeholder: 'Select some tags',
      tags: true

setupSelect2ForTargets = ->
  targetInput = $('#resource_target_id')

  if targetInput.length

    targetInput.select2
      width: '80%',
      minimumInputLength: 3,
      ajax:
        url: '/targets/select2_search',
        dataType: 'json',
        delay: 500,
        data: (params) ->
          return {
            q: params.term
          }
        ,
        processResults: (data, params) ->
          return { results: data }
        cache: true

$(document).on 'turbolinks:load', ->
  if $('.formtastic.resource').length
    setupSelect2ForTargets()
