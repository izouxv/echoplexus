pgpPassphraseModalTemplate = require("./templates/pgpPassphraseModal.html")

PGPPassphraseModal = class PGPPassphraseModal extends Backbone.View
  className: "backdrop"
  template: pgpPassphraseModalTemplate

  events:
    "click #unlock-key": "unlock"
    "click .close-button": "destroy"

  initialize: (opts) ->
    _.bindAll this
    _.extend this, opts

    @$el.html @template()

    $("body").append @$el

  destroy: ->
    @$el.remove()

  unlock: (ev) ->
    $passphraseEl = $("#pgp-passphrase")
    passphrase = $passphraseEl.val()
    $passphraseEl.val("")

    console.log 'trying to unlock'
    try
      usablePrivateKey = @pgp_settings.decryptPrivateKey(passphrase)
      @on_unlock(usablePrivateKey)
      @destroy()
    catch e
      console.error e
      # display an error, try again, etc


module.exports.PGPSettings = class PGPSettings extends Backbone.Model
  initialize: (opts) ->
    # requires channelName
    _.bindAll this
    _.extend this, opts

    this.on "change:armored_keypair", (model, armored_keypair) ->
      priv = openpgp.key.readArmored(armored_keypair?.private)
      pub = openpgp.key.readArmored(armored_keypair?.public)
      uid = priv.keys[0]?.users[0]?.userId?.userid
      fingerprint = priv.keys[0]?.primaryKey?.getFingerprint()
      @set 'user_id', uid if uid
      @set 'fingerprint', fingerprint if fingerprint

    @set 'armored_keypair', localStorage.getObj "pgp:keypair:#{@channelName}"
    @set 'sign?', localStorage.getObj "pgp:sign?:#{@channelName}"
    @set 'encrypt?', localStorage.getObj "pgp:encrypt?:#{@channelName}"


    this.on "change:encrypt? change:sign? change:armored_keypair", @save

  save: ->
    localStorage.setObj "pgp:keypair:#{@channelName}", @get('armored_keypair')
    localStorage.setObj "pgp:sign?:#{@channelName}", @get('sign?')
    localStorage.setObj "pgp:encrypt?:#{@channelName}", @get('encrypt?')

  clear: ->
    @set 'cached_private', null
    @set 'armored_keypair', null
    @set 'sign?', null
    @set 'encrypt?', null

  destroy: ->
    @clear()

    my_fingerprint = @get 'fingerprint'
    KEYSTORE.untrust(my_fingerprint)
    KEYSTORE.clean(my_fingerprint)

  decryptPrivateKey: (passphrase = '') ->
    throw 'Invalid passphrase' if @prev == passphrase and !@get('cached_private')
    @prev = passphrase

    if !@get('cached_private')
      dearmored_privs = openpgp.key.readArmored @get('armored_keypair').private
      decrypted = dearmored_privs.keys[0].decrypt(passphrase)
      if decrypted
        console.log 'decrypted'
        @set 'cached_private', dearmored_privs.keys
      else
        throw "Unable to decrypt private key"
    #else
      #console.log 'using cached priv'

    return @get('cached_private')

  usablePrivateKey: (passphrase = '', callback) ->
    try
      usableKey = @decryptPrivateKey(passphrase)
      callback(usableKey)
    catch
      throw 'Unable to unlock private key'

  sign: (message, callback) ->
    @usablePrivateKey '', (usablePrivateKey) ->
      signed = openpgp.signClearMessage(usablePrivateKey, message)
      callback(signed)

  prompt: (callback) ->
    if @get('cached_private')
      callback(null)
    else
      (new PGPPassphraseModal(
        pgp_settings: this
        on_unlock: ->
          callback(null)
      ))

  usablePublicKey: (armored_public_key) ->
    dearmored_pubs = openpgp.key.readArmored(armored_public_key)
    dearmored_pubs.keys

  encrypt: (pubkey, message) ->
    openpgp.encryptMessage(@usablePublicKey(pubkey), message)

  encryptAndSign: (pubkey, message, callback) ->
    @usablePrivateKey '', (usablePrivateKey) =>
      pub = @usablePublicKey(pubkey)
      signed_encrypted = openpgp.signAndEncryptMessage(pub, usablePrivateKey[0], message)
      callback(signed_encrypted)

  trust: (key) ->
    # mark a key as trusted