/* *****************************************************************************
 * RootPage
 */

open Types
open Constants

let initialDbConnectionStatus = NotConnected
let initialNavigation: option<page> = None

let setOverrideLanguage = (gameState): gameState => {
  let queryStringLanguage =
    QueryString.getQueryParam("lang")
    ->Option.map(x => JSON.String(x))
    ->Option.flatMap(json => json->LanguageCodec.t_decode->Utils.resultToOption)
    ->Option.getOr(gameState.language)
  {
    ...gameState,
    language: queryStringLanguage,
  }
}

let setDefaultLanguage = (gameState): gameState => {
  let browserLanguage = BrowserLanguage.getLanguage()->Option.getOr(gameState.language)
  {
    ...gameState,
    language: browserLanguage,
  }
}

let cleanupGameStateMusic = (gameState): gameState => {
  let knownMusicTracksInclude = x => musicTracks->Array.includes(x)
  {
    ...gameState,
    backgroundMusic: gameState.backgroundMusic->Array.filter(knownMusicTracksInclude),
  }
}

@react.component
let make = (): React.element => {
  let (currentPage, goToPage) = React.useContext(RouterContext.context)

  let (dbConnectionStatus, setDbConnectionStatus) = React.useState(_ => initialDbConnectionStatus)
  let (gameState, setGameState) = React.useState(_ => initialGameState->setDefaultLanguage)
  let (navigation, setNavigation) = React.useState(_ => initialNavigation)
  let (turnState, setTurnState) = React.useState(_ => initialTurnState)

  // Resume a saved multiplayer session with the same role (host stays host, guest stays guest).
  let resumeSession = (savedGameState, savedTurnState, savedCurrentPage) => {
    let sanitizedGameState = savedGameState->cleanupGameStateMusic->setOverrideLanguage
    setGameState(_prev => sanitizedGameState)
    setTurnState(_prev => savedTurnState)
    switch sanitizedGameState.gameType {
    // Master branch: connect, on success setDbConnectionStatus(Connected), call FirebaseClient.updateGame(dbConnection, sanitizedGameState, savedCurrentPage->Option.getOr(Title), savedTurnState, None)
    | Master(_) =>
      setDbConnectionStatus(_prev => ConnectingAsMaster)
      FirebaseClient.connect()
      ->Promise.then(dbConnection => {
        setDbConnectionStatus(_prev => Connected(dbConnection))
        let currentPage = savedCurrentPage->Option.getOr(Title)
        let _ = FirebaseClient.updateGame(dbConnection, sanitizedGameState, currentPage, savedTurnState, None)
        savedCurrentPage->Option.forEach(page => goToPage(_prev => page))
        Promise.resolve()
      })
      ->Promise.catch(error => {
        setDbConnectionStatus(_prev => NotConnected)
        error->Utils.getExceptionMessage->Utils.logError
        Promise.resolve()
      })
      ->ignore
    // Slave branch: connect, on success setDbConnectionStatus(Connected), call FirebaseClient.joinGame(dbConnection, gameId)
    | Slave(gameId) =>
      setDbConnectionStatus(_prev => ConnectingAsSlave)
      FirebaseClient.connect()
      ->Promise.then(dbConnection => {
        setDbConnectionStatus(_prev => Connected(dbConnection))
        let _ = FirebaseClient.joinGame(dbConnection, gameId)
        savedCurrentPage->Option.forEach(page => goToPage(_prev => page))
        Promise.resolve()
      })
      ->Promise.catch(error => {
        setDbConnectionStatus(_prev => NotConnected)
        error->Utils.getExceptionMessage->Utils.logError
        Promise.resolve()
      })
      ->ignore
    | StandAlone => () // unreachable: useEffect0 only dispatches Master(_) | Slave(_)
    }
  }

  // run once after mounting: read localstorage and resume if a session was saved.
  React.useEffect0(() => {
    let session = LocalStorage.loadSession()
    switch session.gameState.gameType {
    | Master(_) | Slave(_) => resumeSession(session.gameState, session.turnState, session.currentPage)
    | StandAlone =>
      LocalStorage.loadGameState()
      ->Option.map(cleanupGameStateMusic)
      ->Option.map(setOverrideLanguage)
      ->Option.forEach(gs => setGameState(_prev => gs))
    }
    None // cleanup function
  })

  // save game state + session to localstorage after every change
  React.useEffect3(() => {
    LocalStorage.saveGameState(gameState)
    switch gameState.gameType {
    | StandAlone => () // do not re-create a cleared session after leaving a multiplayer game
    | Master(_) | Slave(_) => LocalStorage.saveSession(gameState, turnState, currentPage)
    }
    None // cleanup function
  }, (gameState, turnState, currentPage))

  // if we're hosting, save the full game record to firebase when the game state changes
  React.useEffect1(() => {
    Utils.ifMasterAndConnected(dbConnectionStatus, gameState.gameType, (dbConnection, _gameId) => {
      FirebaseClient.saveGameState(dbConnection, gameState, currentPage, turnState, None)
    })
    None // cleanup function
  }, [gameState])

  let currentPageElement = switch currentPage {
  | Title => <TitlePage />
  | Setup => <SetupPage />
  | SetupLanguage => <SetupLanguagePage />
  | SetupMusic => <SetupMusicPage />
  | SetupPlayers => <SetupPlayersPage />
  | SetupNetwork => <SetupNetworkPage noGame=false />
  | SetupNetworkNoGame => <SetupNetworkPage noGame=true />
  | Credits => <CreditsPage />
  | Daytime => <DaytimePage />
  // Master
  | NightDawnOneWitch => <NightScenarioPage subPage=currentPage />
  | NightDawnMoreWitches => <NightScenarioPage subPage=currentPage />
  | NightOtherNoConstable => <NightScenarioPage subPage=currentPage />
  | NightOtherWithConstable => <NightScenarioPage subPage=currentPage />
  // Slave
  | DaytimeWaiting => <SlavePage subPage=currentPage />
  | NightWaiting => <SlavePage subPage=currentPage />
  | NightChoiceWitches => <SlavePage subPage=currentPage />
  | NightConfirmWitches => <SlavePage subPage=currentPage />
  | NightChoiceConstable => <SlavePage subPage=currentPage />
  | NightConfirmConstable => <SlavePage subPage=currentPage />
  // Master
  | DaytimeConfess => <DaytimeConfessPage />
  | DaytimeReveal => <DaytimeRevealPage />
  | DaytimeRevealNoConfess => <DaytimeRevealPage allowBackToConfess=false />
  | Close => <ClosePage />
  }

  <DbConnectionContext.Provider value=(dbConnectionStatus, setDbConnectionStatus)>
    <GameStateContext.Provider value=(gameState, setGameState)>
      <div
        lang={LanguageCodec.getHtmlLanguage(gameState.language)}
        className={gameState.language->LanguageCodec.toString}>
        <NavigationContext.Provider value=(navigation, setNavigation)>
          <TurnStateContext.Provider value=(turnState, setTurnState)>
            {currentPageElement}
          </TurnStateContext.Provider>
        </NavigationContext.Provider>
      </div>
    </GameStateContext.Provider>
  </DbConnectionContext.Provider>
}
