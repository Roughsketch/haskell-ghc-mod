{Range, Point, Directory} = require 'atom'
{delimiter, sep} = require 'path'
Temp = require('temp')
FS = require('fs')

module.exports = Util =
  debug: (messages...) ->
    if atom.config.get('haskell-ghc-mod.debug')
      console.log "haskell-ghc-mod debug:", messages...
      console.trace "haskell-ghc-mod trace:"

  getRootDirFallback: (buffer) ->
    [dir] = atom.project.getDirectories().filter (dir) ->
      dir.contains(buffer.getUri())
    unless dir?
      dir = atom.project.getDirectories()[0]
    if dir?.getPath?() is 'atom://config'
      dir = null
    unless dir?.isDirectory?()
      dir = buffer.file?.getParent?() ? new Directory '.'
    dir

  getRootDir: (buffer) ->
    dirHasCabalFile = (d) ->
      return false unless d?
      d.getEntriesSync().some (file) ->
        file.isFile() and file.getBaseName().endsWith '.cabal'
    dirHasSandboxFile = (d) ->
      return false unless d?
      d.getEntriesSync().some (file) ->
        file.isFile() and (file.getBaseName() is 'cabal.sandbox.config')
    findProjectRoot = (d, check) ->
      until d?.isRoot?() or not d? or check d
        d = d?.getParent?()
      d if check d
    dir = buffer.file?.getParent?() ? Util.getRootDirFallback buffer
    dir = findProjectRoot(dir, dirHasCabalFile) ? findProjectRoot(dir, dirHasSandboxFile)
    unless dir?.isDirectory?()
      dir = Util.getRootDirFallback buffer
    Util.debug "getRootDir path = #{dir.getPath()}",
      "atom.project.getDirectories()[0] = #{atom.project.getDirectories()[0]?.getPath?()}",
      "buffer.file?.getParent?() = #{buffer.file?.getParent?()?.getPath?()}"
    return dir

  getProcessOptions: (rootPath) ->
    Util.debug "getProcessOptions(#{rootPath})"
    env = {}
    for k, v of process.env
      env[k] = v
    apd = atom.config.get('haskell-ghc-mod.additionalPathDirectories')
          .concat process.env.PATH.split delimiter
    if rootPath
      sandbox = "#{rootPath}#{sep}.cabal-sandbox#{sep}bin"
      try if FS.statSync(sandbox).isDirectory()
        apd.unshift sandbox
    env.PATH = "#{apd.join(delimiter)}"
    Util.debug "PATH = #{env.PATH}"
    options =
      cwd: rootPath
      env: env

  getSymbolInRange: (regex, buffer, crange) ->
    if crange.isEmpty()
      {start, end} = buffer.rangeForRow crange.start.row
      crange2 = new Range(crange.start, crange.end)
      buffer.backwardsScanInRange regex, new Range(start, crange.start),
        ({range, stop}) ->
          crange2.start = range.start
      buffer.scanInRange regex, new Range(crange.end, end),
        ({range, stop}) ->
          crange2.end = range.end
    else
      crange2 = crange

    symbol: buffer.getTextInRange crange2
    range: crange2

  withTempFile: (contents, func, suffix, opts) ->
    Temp.open
      prefix: 'haskell-ghc-mod',
      suffix: suffix,
      (err, info) ->
        if err
          atom.notifications.addError "Haskell-ghc-mod: Error when writing
            temp. file",
            detail: "#{err}"
            dismissable: true
          opts.callback []
          return
        FS.writeSync info.fd, contents
        {uri, callback} = opts
        opts.uri = info.path
        opts.callback = (res) ->
          FS.close info.fd, -> FS.unlink info.path
          callback res.map (line) ->
            line.split(info.path).join(uri)
        func opts
