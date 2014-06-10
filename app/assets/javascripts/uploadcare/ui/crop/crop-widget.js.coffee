# = require ./jquery.Jcrop

{
  namespace,
  jQuery: $,
  templates: {tpl},
  utils
} = uploadcare

namespace 'uploadcare.crop', (ns) ->

  class ns.CropWidget

    LOADING_ERROR = 'loadingerror'

    prepareOptions = (options) ->
      fited = utils.fitSizeInCdnLimit options.preferedSize
      if fited[0] isnt options.preferedSize[0]
        willBe = "#{fited.join 'x'}#{if options.upscale then '' else ' or smaller'}"
        utils.warnOnce """
          Specified preferred crop size is bigger than our CDN allows.
          Resulting image size will be #{willBe}.
        """
        options.preferedSize = fited

    # Options:
    #   downscale:
    # If set to `true` "-/resize/%preferedSize%/" will be added
    # if selected area bigger than `preferedSize`. Default false.

    #   upscale:
    # If set to `true` "-/resize/%preferedSize%/" will be added
    # if selected area smaller than `preferedSize`. Default false.

    #   notLess:
    # Restrict selection to preferedSize area. Default false.

    #   preferedSize:
    # Defines image size you want to get at the end.
    # If `downscale` option is set to `false`, it defines only
    # the prefered aspect ratio.
    # If set to `null` any aspect ratio will be acceptable.
    # Array: [123, 123]. (optional)
    constructor: (container, @__options) ->
      @container = $ container
      prepareOptions @__options
      @__buildWidget()

    cropModifierRegExp = /-\/crop\/([0-9]+)x([0-9]+)(\/(center|([0-9]+),([0-9]+)))?\//i

    __parseModifiers: (modifiers) ->
      if raw = modifiers?.match(cropModifierRegExp)
        width: parseInt(raw[1], 10)
        height: parseInt(raw[2], 10)
        center: raw[4] == 'center'
        left: parseInt(raw[5], 10) or undefined
        top: parseInt(raw[6], 10) or undefined

    croppedImageModifiers: (previewUrl, size, modifiers) ->
      @croppedImageCoords(previewUrl, size, @__parseModifiers modifiers)
        .then (coords) =>
          {width: w, height: h} = coords

          opts =
            crop: coords
            modifiers: ''

          changed = w isnt @__originalSize[0] or h isnt @__originalSize[1]
          if changed
            opts.modifiers = "-/crop/#{w}x#{h}/#{coords.left},#{coords.top}/"
            if @__options.preferedSize
              [pw, ph] = @__options.preferedSize
            downscale = @__options.downscale and (w > pw or h > ph)
            upscale = @__options.upscale and (w < pw or h < ph)

            if downscale or upscale
              resized = @__options.preferedSize
            else
              resized = utils.fitSizeInCdnLimit [w, h]

            if resized[0] isnt w or resized[1] isnt h
              [opts.crop.sw, opts.crop.sh] = resized
              opts.modifiers += "-/resize/#{resized.join 'x'}/"
          opts

    croppedImageCoords: (previewUrl, size, coords) ->
      @__calcSizes size
      @__setImage previewUrl
      @__initJcrop coords
      @__deferred = $.Deferred()
      @__deferred.promise()

    # This method could be usefull if you want to make your own done button.
    forceDone: ->
      @__deferred.resolve @__currentCoords

    __buildWidget: ->
      @__widgetElement = $(tpl('crop-widget')).appendTo @container

    __setImage: (@__url) ->
      @__img = $('<img/>')
        .css
          margin: '0 auto'
          width: @__resizedSize[0]
          height: @__resizedSize[1]
        .on 'error', =>
          @__setState 'error'
          @__deferred.reject LOADING_ERROR
          @__img.remove()
        .attr
          src: @__url
          width: @__resizedSize[0]
          height: @__resizedSize[1]
        .appendTo @__widgetElement

    __calcSizes: (originalSize) ->
      @__originalSize = originalSize
      widgetSize = [@container.width(), @container.height() or 640]
      @__resizedSize = utils.fitSize originalSize, widgetSize

    # error
    __setState: (state) ->
      prefix = 'uploadcare-crop-widget--'
      @__widgetElement.addClass(prefix + state)

    __initJcrop: (previousCoords) ->
      jCropOptions =
        handleSize: 10
        trueSize: @__originalSize
        onSelect: (coords) =>
          left = Math.floor Math.max(0, coords.x)
          top = Math.floor Math.max(0, coords.y)
          @__currentCoords = {
            left, top
            width: Math.ceil(Math.min(@__originalSize[0], coords.x2)) - left
            height: Math.ceil(Math.min(@__originalSize[1], coords.y2)) - top
          }

      if @__options.preferedSize
        jCropOptions.aspectRatio =  @__options.preferedSize[0] / @__options.preferedSize[1]

      if not previousCoords
        previousCoords = {center: true}
        if @__options.preferedSize
          [
            previousCoords.width
            previousCoords.height
          ] = utils.fitSize(@__options.preferedSize, @__originalSize, true)
        else
          [previousCoords.width, previousCoords.height] = @__originalSize

      if previousCoords.center
        left = (@__originalSize[0] - previousCoords.width) / 2
        top = (@__originalSize[1] - previousCoords.height) / 2
      else
        left = previousCoords.left or 0
        top = previousCoords.top or 0

      if @__options.notLess
        preferedSize = utils.fitSize @__options.preferedSize, @__originalSize
        jCropOptions.minSize = preferedSize

      jCropOptions.setSelect = [
        left,
        top,
        (previousCoords.width + left),
        (previousCoords.height + top),
      ]

      $.Jcrop(@__img[0], jCropOptions)
