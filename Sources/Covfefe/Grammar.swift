//
//  Grammar.swift
//  Covfefe
//
//  Created by Palle Klewitz on 07.08.17.
//  Copyright (c) 2017 Palle Klewitz
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

/// A syntax error which was generated during parsing or tokenization
public struct SyntaxError: Error {
	
	/// The reason for the syntax error
	///
	/// - emptyNotAllowed: An empty string was provided but the grammar does not allow empty productions
	/// - unknownToken: The tokenization could not be completed because no matching token was found
	/// - unmatchedPattern: A pattern was found which could not be merged
	/// - unexpectedToken: A token was found that was not expected
	public enum Reason {
		/// An empty string was provided but the grammar does not allow empty productions
		case emptyNotAllowed
		
		/// The tokenization could not be completed because no matching token was found
		case unknownToken
		
		/// A pattern was found which could not be merged
		case unmatchedPattern
		
		/// A token was found that was not expected
		case unexpectedToken
	}
	
	/// Range in which the error occurred
	public let range: Range<String.Index>
	
	/// Reason for the error
	public let reason: Reason
	
	/// The context around the error
	public let context: [NonTerminal]
	
	/// The string for which the parsing was unsuccessful
	public let string: String
	
	/// Creates a new syntax error with a given range and reason
	///
	/// - Parameters:
	///   - range: String range in which the syntax error occurred
	///   - string: String which was unsuccessfully parsed
	///   - reason: Reason why the syntax error occurred
	///   - context: Non-terminals which were expected at the location of the error.
	public init(range: Range<String.Index>, in string: String, reason: Reason, context: [NonTerminal] = []) {
		self.range = range
		self.string = string
		self.reason = reason
		self.context = context
	}
}

extension SyntaxError: CustomStringConvertible {
	public var description: String {
		let main = "Error: \(reason) at \(NSRange(range, in: string)): '\(string[range])'"
		if !context.isEmpty {
			return "\(main), expected: \(context.map{$0.description}.joined(separator: " | "))"
		} else {
			return main
		}
	}
}

extension SyntaxError.Reason: CustomStringConvertible {
	public var description: String {
		switch self {
		case .emptyNotAllowed:
			return "Empty string not accepted"
		case .unknownToken:
			return "Unknown token"
		case .unmatchedPattern:
			return "Unmatched pattern"
		case .unexpectedToken:
			return "Unexpected token"
		}
	}
}


/// A context free or regular grammar
/// consisting of a set of productions
///
/// In context free grammars, the left side of productions
/// (in this framework also referred to as pattern) is always
/// a single non-terminal.
///
/// Grammars might be ambiguous. For example, the grammar
///
///		<expr> ::= <expr> '+' <expr> | 'a'
///
/// can recognize the expression `a+a+a+a` in 5 different ways:
/// `((a+a)+a)+a`, `(a+(a+a))+a`, `a+(a+(a+a))`, `a+((a+a)+a)`, `(a+a)+(a+a)`.
public struct Grammar {
	
	/// Productions for generating words of the language generated by this grammar
	public var productions: [Production]
	
	/// Root non-terminal
	///
	/// All syntax trees of words in this grammar must have a root containing this non-terminal.
	public var start: NonTerminal
	
	/// Non-terminals generated by normalizing the grammar.
	let normalizationNonTerminals: Set<NonTerminal>
	
	/// Creates a new grammar with a given set of productions and a start non-terminal
	///
	/// - Parameters:
	///   - productions: Productions for generating words
	///   - start: Root non-terminal
	public init(productions: [Production], start: NonTerminal) {
		self.init(productions: productions, start: start, normalizationNonTerminals: [])
		
		assertNonFatal(unreachableNonTerminals.isEmpty, "Grammar contains unreachable non-terminals (\(unreachableNonTerminals))")
		assertNonFatal(unterminatedNonTerminals.isEmpty, "Grammar contains non-terminals which can never reach terminals (\(unterminatedNonTerminals))")
	}
	
	/// Creates a new grammar with a given set of productions, a start non-terminal and
	/// a set of non-terminals which have been created for normalization
	///
	/// - Parameters:
	///   - productions: Productions for generating words
	///   - start: Root non-terminal
	///   - normalizationNonTerminals: Non-terminals generated during normalization
	init(productions: [Production], start: NonTerminal, normalizationNonTerminals: Set<NonTerminal>) {
		self.productions = productions
		self.start = start
		self.normalizationNonTerminals = normalizationNonTerminals
	}
}


extension Grammar: CustomStringConvertible {
	public var description: String {
		let groupedProductions = Dictionary(grouping: self.productions) { production in
			production.pattern
		}
		return groupedProductions.sorted(by: {$0.key.name < $1.key.name}).map { entry -> String in
			let (pattern, productions) = entry

			let productionString = productions.map { production in
				if production.production.isEmpty {
					return "\"\""
				}
				return production.production.map { symbol -> String in
					switch symbol {
					case .nonTerminal(let nonTerminal):
						return "<\(nonTerminal.name)>"

					case .terminal(let terminal) where terminal.value.contains("\""):
						let escapedValue = terminal.value.literalEscaped
						return "'\(escapedValue)'"

					case .terminal(let terminal):
						let escapedValue = terminal.value.literalEscaped
						return "\"\(escapedValue)\""
					}
				}.joined(separator: " ")
			}.joined(separator: " | ")

			return "<\(pattern.name)> ::= \(productionString)"
		}.joined(separator: "\n")
	}
}

public extension Grammar {
	
	/// Returns true, if the grammar is in chomsky normal form.
	///
	/// A grammar is in chomsky normal form if all productions satisfy one of the following conditions:
	///
	/// - A production generates exactly one terminal symbol
	/// - A production generates exactly two non-terminal symbols
	/// - A production generates an empty string and is generated from the start non-terminal
	///
	/// Certain parsing algorithms, such as the CYK parser, require the recognized grammar to be in Chomsky normal form.
	public var isInChomskyNormalForm: Bool {
		return productions.allMatch { production -> Bool in
			(production.isFinal && production.production.count == 1)
			|| (!production.isFinal && production.generatedNonTerminals.count == 2 && production.generatedTerminals.count == 0)
			|| (production.production.isEmpty && production.pattern == start)
		}
	}
}

extension Grammar: Equatable {
	public static func == (lhs: Grammar, rhs: Grammar) -> Bool {
		return lhs.start == rhs.start && Set(lhs.productions) == Set(rhs.productions)
	}
}
