/* *****************************************************************************
 * GameIdWithQr
 */

open Types

let p = "[GameIdWithQr] "

@val external copyTextToClipboard: string => promise<unit> = "navigator.clipboard.writeText"

let copiedMessageDelay = 1500 // milliseconds

@react.component
let make = (~gameId: string, ~children: React.element=React.null): React.element => {
  let (gameState, _) = React.useContext(GameStateContext.context)
  let t = Translator.getTranslator(gameState.language)
  let (showCopied, setShowCopied) = React.useState(_ => false)

  // Hides the "Copied!" bubble again after a short delay
  React.useEffect1(() => {
    if showCopied {
      let timerId = Js.Global.setTimeout(() => {
        setShowCopied(_prev => false)
      }, copiedMessageDelay)
      Some(() => Js.Global.clearTimeout(timerId))
    } else {
      None
    }
  }, [showCopied])

  let copyCode: clickHandler = _event => {
    Utils.logDebug(p ++ "Copying gameId to clipboard")
    switch Utils.safeExec(() => copyTextToClipboard(gameId)) {
    | None => Utils.logDebug(p ++ "Clipboard API not available")
    | Some(promise) =>
      promise
      ->Promise.then(() => {
        setShowCopied(_prev => true)
        Promise.resolve()
      })
      ->Utils.catchLogAndIgnore()
    }
  }

  <div className="input-and-icon">
    <div className="id-input" onClick=copyCode>
      {React.string(gameId)}
    </div>
    <QrIcon mode={QrIcon.Scannable(gameId)} />
    {
      // Reuse the status bubble slot: temporarily show "Copied!" and restore it afterwards.
      if showCopied {
        <Bubble dir=North> {React.string(t("Copied!"))} </Bubble>
      } else {
        children
      }
    }
  </div>
}