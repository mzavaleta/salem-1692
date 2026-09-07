/* *****************************************************************************
 * LocalStorage
 */

open Types
open Utils

let setItem = (key: string, value: string): unit => {
  Dom.Storage2.localStorage->Dom.Storage2.setItem(key, value)
}

let getItem = (key: string): option<string> => {
  Dom.Storage2.localStorage->Dom.Storage2.getItem(key)
}

let gameStateKey = Constants.localStoragePrefix ++ Constants.localStorageGameStateKey

let loadGameState = (): option<gameState> => {
  Dom.Storage2.localStorage
  ->Dom.Storage2.getItem(gameStateKey) // this yields an option<string>
  ->Option.flatMap(jsonString => safeExec(() => jsonString->JSON.parseExn)) // this yields an option<JSON.t>
  ->Option.flatMap(str => str->gameState_decode->Result.mapOr(None, x => Some(x)))
}

let saveGameState = (gameState: gameState): unit => {
  gameState
  ->gameState_encode
  ->JSON.stringifyAny
  ->Option.forEach(jsonGameState => setItem(gameStateKey, jsonGameState))
}

/* *************************************************************************
 * Session persistence (gameState + turnState + currentPage)
 *
 * A new key `salem1692.session` stores the full snapshot as JSON:
 *   { "gameState": ..., "turnState": ..., "currentPage": "..." }
 * Falls back to legacy `salem1692.gameState` when the new key is absent.
 * ************************************************************************* */

type session = {
  gameState: gameState,
  turnState: turnState,
  currentPage: option<page>,
}

let sessionKey = Constants.localStoragePrefix ++ Constants.localStorageSessionKey

let saveSession = (gameState: gameState, turnState: turnState, currentPage: page): unit => {
  let json =
    JSON.Encode.object(Dict.fromArray([
      ("gameState", gameState->gameState_encode),
      ("turnState", turnState->turnState_encode),
      ("currentPage", JSON.Encode.string(currentPage->pageToString)),
    ]))
  json->JSON.stringifyAny->Option.forEach(str => setItem(sessionKey, str))
}

let loadSession = (): session =>
  getItem(sessionKey)
  ->Option.flatMap(jsonStr => safeExec(() => jsonStr->JSON.parseExn))
  ->Option.flatMap(json => {
    json
    ->JSON.Decode.object
    ->Option.flatMap(dict => {
      let gameState =
        dict
        ->Dict.get("gameState")
        ->Option.flatMap(j => j->gameState_decode->Result.mapOr(None, x => Some(x)))
      let turnState =
        dict
        ->Dict.get("turnState")
        ->Option.flatMap(j => j->turnState_decode->Result.mapOr(None, x => Some(x)))
      let currentPage =
        dict
        ->Dict.get("currentPage")
        ->Option.flatMap(j => j->JSON.Decode.string)
        ->Option.flatMap(pageOfString)
      gameState->Option.flatMap(gs =>
        turnState->Option.map(ts => {gameState: gs, turnState: ts, currentPage})
      )
    })
  })
  ->Option.getOr({
    gameState: Constants.initialGameState,
    turnState: Constants.initialTurnState,
    currentPage: None,
  })

let clearSession = (): unit => Dom.Storage2.localStorage->Dom.Storage2.removeItem(sessionKey)
