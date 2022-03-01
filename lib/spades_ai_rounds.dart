import 'dart:math';

import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/spades/spades.dart';
import 'package:cards_with_cats/spades/spades_ai.dart';

import 'cards/card.dart';

/*
Results of Monte Carlo AIs playing against each other for 1000 rounds:

100% chooseCardToMakeBids vs 50/50 random/chooseCardToMakeBids: 322 to 678
50/50 random/chooseCardToMakeBids vs 100% random: 532 to 468
100% chooseCardToMakeBids vs 100% random: 346 to 654

So random rollouts seem to be better than "smart", with a mix possibly slightly better.
 */

void main() {
  final rules = SpadesRuleSet();
  final teamMatchWins = List.filled(rules.numTeams, 0);
  final rng = Random();
  const numMatchesToPlay = 10;
  int totalRounds = 0;

  for (int matchNum = 1; matchNum <= numMatchesToPlay; matchNum++) {
    print("Match #$matchNum");
    SpadesMatch match = SpadesMatch(rules, rng);
    int roundNum = 0;
    while (!match.isMatchOver()) {
      roundNum += 1;
      totalRounds += 1;
      final round = match.currentRound;
      print("Round $roundNum (total $totalRounds), P${round.dealer} deals");
      for (int i = 0; i < rules.numPlayers; i++) {
        print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
      }
      List<int> otherBids = [];
      for (int notPlayerIndex = 0; notPlayerIndex < rules.numPlayers; notPlayerIndex++) {
        int pnum = (round.dealer + 1 + notPlayerIndex) % rules.numPlayers;
        final bidReq = BidRequest(
          rules: round.rules,
          scoresBeforeRound: round.initialScores,
          otherBids: otherBids,
          hand: round.players[pnum].hand,
        );
        final bid = chooseBid(bidReq);
        otherBids.add(bid);
        print("P$pnum bids $bid");
        round.setBidForPlayer(bid: bid, playerIndex: pnum);
      }
      while (!round.isOver()) {
        final result = computeCardToPlay(round, rng);
        print(
            "P${round.currentPlayerIndex()} plays ${result.bestCard.symbolString()} (${result.toString()})");
        round.playCard(result.bestCard);
        if (round.currentTrick.cards.isEmpty) {
          print("P${round.previousTricks.last.winner} takes the trick");
        }
      }
      print("Scores for round $roundNum: ${round.pointsTaken().map((s) => s.totalRoundPoints)}");
      match.finishRound();
      print("Scores for match: ${match.scores}");
    }
    print("Match over");
    final winner = match.winningTeam();
    print("Team $winner wins");
    teamMatchWins[winner!] += 1;
    print("Total wins: $teamMatchWins");
    print("====================================");
  }
}

final mcParams = MonteCarloParams(maxRounds: 50, rolloutsPerRound: 20);

ChooseCardFn makeMixedRandomMakeBidsFn(double randomProb) {
  return (req, rng) =>
      rng.nextDouble() < randomProb ? chooseCardToMakeBids(req, rng) : chooseCardRandom(req, rng);
}

MonteCarloResult computeCardToPlay(final SpadesRound round, Random rng) {
  final cardReq = CardToPlayRequest.fromRound(round);
  switch (round.currentPlayerIndex()) {
    case 0:
    case 2:
      return chooseCardMonteCarlo(cardReq, mcParams, makeMixedRandomMakeBidsFn(1.0), rng);
    case 1:
    case 3:
      return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardToMakeBids(cardReq, rng));
    default:
      throw Exception("Bad player index: ${round.currentPlayerIndex()}");
  }
}
