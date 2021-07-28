import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hearts/cards/rollout.dart';
import 'package:hearts/hearts/hearts.dart';
import 'package:hearts/hearts/hearts_ai.dart';

import 'cards/card.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CatTricks',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'CatTricks'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AnimationMode {
  none,
  moving_passed_cards,
  moving_trick_card,
  moving_trick_to_winner,
}

class Layout {
  late Size displaySize;
  late double edgePx;

  Rect cardArea() {
    return Rect.fromLTRB(edgePx, edgePx, displaySize.width - edgePx, displaySize.height - edgePx);
  }

  Size baseCardSize() {
    final ca = cardArea();
    return Size(ca.width * 0.4, ca.height * 0.4);
  }

  Rect trickCardAreaForPlayer(int playerIndex) {
    final ca = cardArea();
    final cs = baseCardSize();
    final centerXFrac = (playerIndex == 1) ?
        0.25 :
        (playerIndex == 3) ? 0.75 : 0.5;
    final centerYFrac = (playerIndex == 0) ?
        0.75 :
        (playerIndex == 2) ? 0.25 : 0.5;
    final centerX = ca.left + ca.width * centerXFrac;
    final centerY = ca.top + ca.height * centerYFrac;
    return Rect.fromLTWH(centerX - cs.width / 2, centerY - cs.height / 2, cs.width, cs.height);
  }

  Rect cardOriginAreaForPlayer(int playerIndex) {
    final w = displaySize.width;
    final h = displaySize.height;
    final ca = cardArea();
    final cardHeight = ca.height * 0.4;
    final cardWidth = ca.width * 0.4;
    switch (playerIndex) {
      case 0:
        return Rect.fromCenter(
            center: Offset(w / 2, h + cardHeight / 2), width: cardWidth, height: cardHeight);
      case 1:
        return Rect.fromCenter(
            center: Offset(-cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      case 2:
        return Rect.fromCenter(
            center: Offset(w / 2, -cardHeight / 2), width: cardWidth, height: cardHeight);
      case 3:
        return Rect.fromCenter(
            center: Offset(w  + cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      default:
        throw Exception("Bad player index: $playerIndex");
    }
  }
}

PlayingCard computeCard(final CardToPlayRequest req) {
  return chooseCardMonteCarlo(
      req,
      MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
      chooseCardAvoidingPoints,
      Random());
}

class _MyHomePageState extends State<MyHomePage> {
  final rng = Random();
  final rules = HeartsRuleSet();
  var animationMode = AnimationMode.none;
  late HeartsRound round;

  @override void initState() {
    super.initState();
    round = HeartsRound.deal(rules, List.filled(4, 0), 0, rng);
    Future.delayed(Duration(milliseconds: 500), () => _playNextCard());
  }

  void _scheduleNextPlayIfNeeded() {
    if (round.isOver()) {
      setState(() {
        round = HeartsRound.deal(rules, List.filled(4, 0), 0, rng);
      });
    }
    if (round.currentPlayerIndex() != 0) {
      Future.delayed(Duration(milliseconds: 500), () => _playNextCard());
    }
  }

  void _playCard(final PlayingCard card) {
    setState(() {
      round.playCard(card);
      animationMode = AnimationMode.moving_trick_card;
    });
  }

  void _trickCardAnimationFinished() {
    setState(() {animationMode = AnimationMode.none;});
    _scheduleNextPlayIfNeeded();
  }

  void _playNextCard() async {
    // Do this in a separate thread/isolate.
    final card = await compute(computeCard, CardToPlayRequest.fromRound(round));
    _playCard(card);
  }
  
  void handleHandCardClicked(final PlayingCard card) {
    print("Clicked ${card.toString()}");
    if (round.status == HeartsRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        _playCard(card);
      }
    }
  }

  Widget _positionedCard(final Rect rect, final PlayingCard card, {double opacity = 1.0}) {
    final cardImagePath = "assets/cards/${card.toString()}.webp";
    final backgroundImagePath = "assets/cards/black.webp";
    return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: GestureDetector(
            onTapDown: (tap) => handleHandCardClicked(card),
            child: Stack(children: [
              if (opacity < 1) Image(
                image: AssetImage(backgroundImagePath),
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
              Image(
                color: Color.fromRGBO(255, 255, 255, opacity),
                colorBlendMode: BlendMode.modulate,
                image: AssetImage(cardImagePath),
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ])));
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    final cardWidthFrac = 0.15;
    final cardOverlapWidthFrac = 0.1;
    final totalWidthFrac = (int n) => cardWidthFrac + (n - 1) * cardOverlapWidthFrac;
    final cardWidth = cardWidthFrac * layout.displaySize.width;

    final cardHeightFrac = 0.2;
    final cardHeight = cardHeightFrac * layout.displaySize.height;

    final upperRowHeightFracStart = 0.65;
    final lowerRowHeightFracStart = 0.75;
    final List<Widget> cardImages = [];

    List sortedCards = [
      ...sortedCardsInSuit(cards, Suit.hearts),
      ...sortedCardsInSuit(cards, Suit.spades),
      ...sortedCardsInSuit(cards, Suit.diamonds),
      ...sortedCardsInSuit(cards, Suit.clubs),
    ];
    bool isHumanTurn = round.currentPlayerIndex() == 0;
    final playableCards = isHumanTurn ? round.legalPlaysForCurrentPlayer() : [];
    final makeCardWidget = (Rect rect, PlayingCard card) =>
        _positionedCard(rect, card, opacity: playableCards.contains(card) ? 1.0 : 0.5);

    if (sortedCards.length > 7) {
      final numUpperCards = (sortedCards.length + 1) ~/ 2;
      final numLowerCards = sortedCards.length - numUpperCards;
      final upperWidthFrac = totalWidthFrac(numUpperCards);
      final upperStartX = 0.5 - upperWidthFrac / 2;
      for (int i = 0; i < numUpperCards; i++) {
        final left = (upperStartX + (cardOverlapWidthFrac * i)) * layout.displaySize.width;
        final top = upperRowHeightFracStart * layout.displaySize.height;
        Rect cardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
        cardImages.add(makeCardWidget(cardRect, sortedCards[i]));
      }
      for (int i = 0; i < numLowerCards; i++) {
        final left = (upperStartX + (cardOverlapWidthFrac * (i + 0.5))) * layout.displaySize.width;
        final top = lowerRowHeightFracStart * layout.displaySize.height;
        Rect cardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
        cardImages.add(makeCardWidget(cardRect, sortedCards[numUpperCards + i]));
      }
    }
    else {
      final startX = 0.5 - totalWidthFrac(sortedCards.length) / 2;
      for (int i = 0; i < sortedCards.length; i++) {
        final left = (startX + (cardOverlapWidthFrac * i)) * layout.displaySize.width;
        final top = lowerRowHeightFracStart * layout.displaySize.height;
        Rect cardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
        cardImages.add(makeCardWidget(cardRect, sortedCards[i]));
      }
    }
    return Stack(children: cardImages);
  }

  Widget _trickCardForPlayer(final Layout layout, final PlayingCard card, int playerIndex) {
    final cardRect = layout.trickCardAreaForPlayer(playerIndex);
    return _positionedCard(cardRect, card);
  }

  List<Widget> _staticTrickCards(
      final Layout layout, int leader, int numPlayers, List<PlayingCard> cards) {
    List<Widget> cardWidgets = [];
    for (int i = 0; i < cards.length; i++) {
      int p = (leader + i) % numPlayers;
      cardWidgets.add(_trickCardForPlayer(layout, cards[i], p));
    }
    return cardWidgets;
  }

  List<Widget> _trickCardsWithLastAnimating(
      final Layout layout, int leader, int numPlayers, List<PlayingCard> cards) {
    final cardsWithoutLast = cards.sublist(0, cards.length - 1);
    List<Widget> cardWidgets =
        List.of(_staticTrickCards(layout, leader, numPlayers, cardsWithoutLast));
    final animPlayer = (leader + cards.length - 1) % numPlayers;
    cardWidgets.add(TweenAnimationBuilder(
        tween: Tween(
            begin: layout.cardOriginAreaForPlayer(animPlayer).center,
            end: layout.trickCardAreaForPlayer(animPlayer).center),
        duration: const Duration(milliseconds: 200),
        onEnd: _trickCardAnimationFinished,
        builder: (BuildContext context, Offset center, Widget? child) {
          final cardSize = layout.baseCardSize();
          final animRect = Rect.fromCenter(center: center, width: cardSize.width, height: cardSize.height);
          return _positionedCard(animRect, cards.last);
        }));

    return cardWidgets;
  }

  Widget _trickCards(final Layout layout) {
    List<Widget> cardWidgets = [];
    if (round.currentTrick.cards.isNotEmpty) {
      if (animationMode == AnimationMode.moving_trick_card) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, round.currentTrick.leader, round.rules.numPlayers, round.currentTrick.cards));
      }
      else {
        cardWidgets.addAll(_staticTrickCards(
            layout, round.currentTrick.leader, round.rules.numPlayers, round.currentTrick.cards));
      }
    }
    else if (round.previousTricks.isNotEmpty) {
      final trick = round.previousTricks.last;
      if (animationMode == AnimationMode.moving_trick_card) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, trick.leader, round.rules.numPlayers, trick.cards));
      }
      else {
        cardWidgets.addAll(_staticTrickCards(
            layout, trick.leader, round.rules.numPlayers, trick.cards));
      }
    }
    return Stack(children: cardWidgets);
  }

  Widget _aiPlayerWidget(final Layout layout, int playerIndex) {
    final imagePath = "assets/cats/cat${playerIndex + 1}.png";
    final imageAspectRatio = 156 / 112;
    final displaySize = layout.displaySize;
    final playerSize = layout.edgePx;

    final rect = (() {
      switch (playerIndex) {
        case 0:
          return Rect.fromLTWH(0, displaySize.height - playerSize, displaySize.width, playerSize);
        case 1:
          return Rect.fromLTWH(0, 0, playerSize, displaySize.height);
        case 2:
          return Rect.fromLTWH(0, 0, displaySize.width, playerSize);
        case 3:
          return Rect.fromLTWH(displaySize.width - playerSize, 0, playerSize, displaySize.height);
        default:
          return Rect.fromLTWH(0, 0, 0, 0);
      }
    })();
    final angle = (playerIndex - 2) * pi / 2;
    final scale = (playerIndex == 1 || playerIndex == 3) ? imageAspectRatio : 1.0;

    return Positioned(
      top: rect.top,
      left: rect.left,
      width: rect.width,
      height: rect.height,

      child: Container(
        color: Colors.white70,
        width: rect.width,
        height: rect.height,
        // The image won't naturally take up the full width If rotated 90 degrees,
        // so in that case scale by the aspect ratio.
        child: Transform.scale(scale: scale, child: Transform.rotate(angle: angle, child: Image(
          image: AssetImage(imagePath),
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ))),
      ),

      // child: Text("Hello $playerNum"),
    );
  }

  Layout computeLayout() {
    final ds = MediaQuery.of(context).size;
    return Layout()
        ..displaySize = ds
        ..edgePx = max(ds.width / 20, ds.height / 15)
        ;
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout();

    return Scaffold(
      body: Stack(
          children: <Widget>[
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.green,
            ),
            ...[0, 1, 2, 3].map((i) => _aiPlayerWidget(layout, i)),
            _trickCards(layout),
            _handCards(layout, round.players[0].hand),
          ],
        ),
    );
  }
}
