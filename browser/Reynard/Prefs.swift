//
  //  Prefs.swift
  //  Reynard
  //

  import Foundation

  enum Prefs {
      enum JITSettings {
          private static let isJITEnabledKey = "Prefs.JITSettings.isJITEnabled"

          static var isJITEnabled: Bool {
              get { UserDefaults.standard.bool(forKey: isJITEnabledKey) }
              set { UserDefaults.standard.set(newValue, forKey: isJITEnabledKey) }
          }
      }
  }
  