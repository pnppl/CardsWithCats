
import 'dart:math';

import 'package:hearts/cards/rollout.dart';
import 'package:hearts/hearts/hearts.dart';
import 'package:hearts/hearts/hearts_ai.dart';

import 'cards/card.dart';

void main() {
  final rules = HeartsRuleSet();
  final victoryPoints = List.filled(rules.numPlayers, 0);
  final rng = Random();
  int totalRounds = 0;

  for (int matchNum = 1; matchNum <= 10; matchNum++) {
    print("Match #$matchNum");
    HeartsMatch match = HeartsMatch(rules, rng);
    int roundNum = 0;
    while (!match.isMatchOver()) {
      roundNum += 1;
      totalRounds += 1;
      final passDir = match.passDirection;
      print("Round $roundNum (total $totalRounds)");
      final round = match.currentRound;
      for (int i = 0; i < rules.numPlayers; i++) {
        print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
      }
      if (passDir != 0) {
        print("Passing dir=$passDir");
        for (int i = 0; i < rules.numPlayers; i++) {
          final passReq = CardsToPassRequest(
              rules: rules,
              scoresBeforeRound: List.of(round.initialScores),
              hand: round.players[i].hand,
              direction: passDir,
              numCards: rules.numPassedCards,
          );
          final cardsToPass = chooseCardsToPass(passReq);
          round.setPassedCardsForPlayer(i, cardsToPass);
          print("P$i passes $cardsToPass");
        }
        round.passCards();
        print("After passing:");
        for (int i = 0; i < rules.numPlayers; i++) {
          print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
        }
      }
      else {
        print("No passing");
      }
      while (!round.isOver()) {
        final card = computeCardToPlay(round, rng);
        print("P${round.currentPlayerIndex()} plays ${card.symbolString()}");
        round.playCard(card);
        if (round.currentTrick.cards.isEmpty) {
          print("P${round.previousTricks.last.winner} takes the trick");
        }
      }
      print("Scores for round $roundNum: ${round.pointsTaken()}");
      match.finishRound();
      print("Scores for match: ${match.scores}");
    }
    print("Match over");
    final vp = getVictoryPoints(match);
    print("Victory points for match: $vp");
    for (int i = 0; i < rules.numPlayers; i++) {
      victoryPoints[i] += vp[i];
    }
    print("Total victory points: $victoryPoints");
    print("====================================");
  }
}

final mcParams = MonteCarloParams(numHands: 50, rolloutsPerHand: 20);
final mixedStrategy20PercentRandom = makeMixedRandomOrAvoidPoints(0.2);

PlayingCard computeCardToPlay(final HeartsRound round, Random rng) {
  final cardReq = CardToPlayRequest.fromRound(round);
  switch (round.currentPlayerIndex()) {
    case 0:
      return chooseCardAvoidingPoints(cardReq, rng);
    case 1:
      return chooseCardMonteCarlo(cardReq, mcParams, mixedStrategy20PercentRandom, rng);
    case 2:
      return chooseCardMonteCarlo(cardReq, mcParams, chooseCardRandom, rng);
    case 3:
      return chooseCardMonteCarlo(cardReq, mcParams, chooseCardAvoidingPoints, rng);
    default:
      throw Exception("Bad player index: ${round.currentPlayerIndex()}");
  }
}

List<int> getVictoryPoints(HeartsMatch match) {
  final winners = match.winningPlayers();
  return List.generate(match.rules.numPlayers,
          (i) => winners.contains(i) ? 12 ~/ winners.length : 0);
}
