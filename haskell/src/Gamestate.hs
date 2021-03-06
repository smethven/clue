module Gamestate where

import Text.Read (readMaybe)

-- Battleship are two 10*10 grids, x-axis: A-J, y-axis: 0-9

-- ships cover squares on the grid
-- 1 carrier: 5 squares long
-- 1 battleship: 4 squares long
-- 1 cruiser: 3 squares long
-- 1 submarine: 3 squares long
-- 1 destroyer: 2 squares long

-- GameState BattleshipState BoardView
data GameState = GameState BattleshipState BoardView

-- BattleshipState YourState [PreviousAttacks]
data BattleshipState = BSS PlayerState [GridSquare]

-- YourGrid [Ships] [Hits]
data PlayerState = PlayerState [Ship] [GridSquare]

-- a well-formed ship has all gridsquares in a line
data Ship = Ship [GridSquare]

data GridSquare = Square XCoord YCoord
  deriving (Eq, Show, Read)

data XCoord = A | B | C | D | E | F | G | H | I | J
  deriving (Bounded, Enum, Show, Read, Eq, Ord)
data YCoord = Zero | One | Two | Three | Four | Five | Six | Seven | Eight | Nine
  deriving (Bounded, Enum, Show, Read, Eq, Ord)

-- BV YourBoard OpponentBoard
data BoardView = BV [[String]] [[String]]

-- Response Attacked Hit SunkShip WonGame
-- A response is a response to an attack that is sent back to the opponent, thus wongame means opponent won game and we lost
data Response = Response GridSquare Bool Bool Bool
  deriving (Show, Read)
type Attack = GridSquare

data UpdateType = ShipSquare | Hit | Miss

-- Constants
serverStartState :: GameState
serverStartState = GameState serverBattleshipState serverBoardView

serverBattleshipState :: BattleshipState
serverBattleshipState = BSS serverPlayerState []

serverPlayerState :: PlayerState
serverPlayerState = PlayerState [Ship [Square B One, Square C One, Square D One, Square E One, Square F One],
                                 Ship [Square I One, Square I Two, Square I Three, Square I Four],
                                 Ship [Square C Three, Square D Three, Square E Three],
                                 Ship [Square A Six, Square A Seven, Square A Eight],
                                 Ship [Square H Nine, Square I Nine]] []

serverBoardView :: BoardView
serverBoardView = BV (buildNewBoard serverPlayerState) emptyBoard

clientStartState :: GameState
clientStartState = GameState clientBattleshipState clientBoardView

clientBattleshipState :: BattleshipState
clientBattleshipState = BSS clientPlayerState []

clientPlayerState :: PlayerState
clientPlayerState = PlayerState [Ship [Square C Nine, Square D Nine, Square E Nine, Square F Nine, Square G Nine],
                                 Ship [Square E Four, Square E Five, Square E Six, Square E Seven],
                                 Ship [Square A One, Square A Two, Square A Three],
                                 Ship [Square C One, Square D One, Square E One],
                                 Ship [Square J Five, Square I Five]] []

clientBoardView :: BoardView
clientBoardView = BV (buildNewBoard clientPlayerState) emptyBoard

emptyBoard :: [[String]]
emptyBoard = replicate 10 (replicate 10 "~")

boardWidth :: Int
boardWidth = 21

boardSpacerSize :: Int
boardSpacerSize = 5

headerSpacerSize :: Int
headerSpacerSize = boardSpacerSize + 16

boardViewHeader :: String
boardViewHeader = "Your Board:" ++ replicate headerSpacerSize ' ' ++ "Opponent's Board:"

boardHeader :: String
boardHeader = unwords $ spacer ++ header ++ replicate boardSpacerSize " " ++ spacer ++ header
  where header = map show [A ..J]
        spacer = [" "]

totalShipLength :: Int
totalShipLength = 17


-- Functions

notPrevAttack :: Attack -> GameState -> Bool
notPrevAttack attack (GameState (BSS _ pvAttacks) _) = notElem attack pvAttacks

-- given an attack from opponent, and player's current game state, create response
makeResponseFromAttack :: Attack -> GameState -> Response
makeResponseFromAttack attack gs | doesAttackMakeUsLose attack gs = Response attack True True True
                                 | doesAttackSinkShip attack gs = Response attack True True False
                                 | isAttackHit attack gs = Response attack True False False
                                 | otherwise = Response attack False False False

-- given an attack from opponent, and player's current game state, does the attack sink our last ship and make us lose
doesAttackMakeUsLose :: Attack -> GameState -> Bool
doesAttackMakeUsLose attack (GameState (BSS playerState attacks) bv) = (length hits == totalShipLength-1) && (isAttackHit attack (GameState (BSS playerState attacks) bv))
  where (PlayerState ships hits) = playerState

-- given an attack from opponent, and player's current game state, does the attack sink a ship
doesAttackSinkShip :: Attack -> GameState -> Bool
doesAttackSinkShip attack (GameState (BSS playerState attacks) bv) = any (isShipHit attack) (filter (isShipAlmostSunk playerState) ships)
  where (PlayerState ships hits) = playerState

-- given an attack from opponent, and player's current game state, were any ships hit
isAttackHit :: Attack -> GameState -> Bool
isAttackHit attack (GameState (BSS playerState attacks) bv) = (length (filter (== True) (map (isShipHit attack) ships))) == 1
  where (PlayerState ships hits) = playerState

-- given an attack, is the ship hit
isShipHit :: Attack -> Ship -> Bool
isShipHit (Square x y) (Ship squares) = (length (filter (== (Square x y)) squares)) == 1

-- returns true if the ship is 1 hit away from being sunk
isShipAlmostSunk :: PlayerState -> Ship -> Bool
isShipAlmostSunk playerState (Ship squares) = (numberOfHitsOnShip squares playerState) == ((length squares) -1)

-- given a ship's gridsquares and a player state, how many hits are on the ship
numberOfHitsOnShip :: [GridSquare] -> PlayerState -> Int
numberOfHitsOnShip [] (PlayerState ships hits) = 0
numberOfHitsOnShip (head:tail) (PlayerState ships hits)
  | elem head hits = 1 + numberOfHitsOnShip tail (PlayerState ships hits)
  | otherwise = numberOfHitsOnShip tail (PlayerState ships hits)

updateOnAttack :: Attack -> GameState -> GameState
updateOnAttack attack gs =
  GameState (BSS (PlayerState ships (strike ++ hits)) pa) (updateBV player attack hit bv)
  where (GameState bss bv) = gs
        (BSS ps pa) = bss
        (PlayerState ships hits) = ps
        player = False
        hit = isAttackHit attack gs
        strike = if hit then [attack] else []

updateOnResponse :: Response -> GameState -> GameState
updateOnResponse (Response square hit sunk won) (GameState bss bv) =
  GameState (updateBSSOnResponse square bss) (updateBV opponent square hit bv)
  where opponent = True

updateBSSOnResponse :: GridSquare -> BattleshipState -> BattleshipState
updateBSSOnResponse attack (BSS state attacks) = BSS state (attack:attacks)

updateBV :: Bool -> GridSquare -> Bool -> BoardView -> BoardView
updateBV True square hit (BV playerBoard oppBoard) =
  BV playerBoard (updateBoard square update oppBoard)
    where update = if hit then Hit else Miss
updateBV False square hit (BV playerBoard oppBoard) =
  BV (updateBoard square update playerBoard) oppBoard
    where update = if hit then Hit else Miss

updateBoard :: GridSquare -> UpdateType -> [[String]] -> [[String]]
updateBoard _ _ [] = []
updateBoard (Square xCoord Zero) update (l:lines) = updateLine x update l:lines
  where x = fromEnum xCoord
updateBoard (Square xCoord yCoord) update (l:lines) =
  l:updateBoard (Square xCoord (pred yCoord)) update lines

updateLine :: Int -> UpdateType -> [String] -> [String]
updateLine _ _ [] = []
updateLine 0 Hit (_:rest) = "X":rest
updateLine 0 Miss (_:rest) = "O":rest
updateLine 0 ShipSquare (_:rest) = "S":rest
updateLine x hit (l:rest) = l:updateLine (x-1) hit rest

buildNewBoard :: PlayerState -> [[String]]
buildNewBoard (PlayerState ships _) = buildOnBoard ships emptyBoard
  where buildOnBoard [] board = board
        buildOnBoard (ship:ships) board = createShip ship (buildOnBoard ships board)

createShip :: Ship -> [[String]] -> [[String]]
createShip (Ship []) board = board
createShip (Ship (sqr:sqrs)) lines = updateBoard sqr ShipSquare updatedLines
  where updatedLines = createShip (Ship sqrs) lines

showBoards :: BoardView -> String
showBoards (BV player opponent) = unlines [boardViewHeader, boardHeader,
                                           combineLines Zero player opponent,
                                           combineLines One player opponent,
                                           combineLines Two player opponent,
                                           combineLines Three player opponent,
                                           combineLines Four player opponent,
                                           combineLines Five player opponent,
                                           combineLines Six player opponent,
                                           combineLines Seven player opponent,
                                           combineLines Eight player opponent,
                                           combineLines Nine player opponent]

combineLines :: YCoord -> [[String]] -> [[String]] -> String
combineLines y playerLines oppLines =
  unwords $ head ++ playerLine ++ replicate boardSpacerSize " " ++ head ++ opponentLine
  where head = [show (fromEnum y)]
        coord = fromEnum y
        playerLine = playerLines!!coord
        opponentLine = oppLines!!coord

parseAttack :: String -> Maybe Attack
parseAttack str = maybeAttack maybeX maybeY
  where coords = words str
        maybeX = getXCoord coords
        maybeY = getYCoord coords

maybeAttack :: Maybe XCoord -> Maybe YCoord -> Maybe Attack
maybeAttack Nothing _ = Nothing
maybeAttack _ Nothing = Nothing
maybeAttack (Just xcoord) (Just ycoord) = Just (Square xcoord ycoord)

getXCoord :: [String] -> Maybe XCoord
getXCoord [x, _]= readMaybe x
getXCoord _ = Nothing

getYCoord :: [String] -> Maybe YCoord
getYCoord [_, y] = toYCoord num
  where num = readMaybe y :: Maybe Int
getYCoord _ = Nothing

toYCoord :: Maybe Int -> Maybe YCoord
toYCoord Nothing = Nothing
toYCoord (Just y) | y >= 0 && y < 10 = Just (toEnum y)
                  | otherwise = Nothing

attackLocation :: XCoord -> YCoord -> String
attackLocation x y = (show x) ++ " " ++ (show (fromEnum y))
