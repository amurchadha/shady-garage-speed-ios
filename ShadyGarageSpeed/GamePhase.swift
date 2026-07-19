// GamePhase.swift — phase state machine states (mirrors main.js PHASES).
// menu → setup → garage ⇄ build → race → results → garage
enum GamePhase { case menu, setup, garage, build, race, results }
