{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Distributed.Raft.Types where

import Control.Lens hiding (Index)
import Data.Aeson (FromJSON, ToJSON)
import Data.HashMap.Strict (HashMap)
import Data.HashSet (HashSet)
import Data.Sequence (Seq)
import Data.Time (DiffTime)
import GHC.Generics (Generic)
import UnliftIO.Async (Async)

class Transition state where
  type Update state
  transition :: state -> Update state -> state

data Logs event = Logs
  { logs :: !(Seq event)
  , committedCount :: !Int
  }
  deriving
    (Show, Eq, Ord, Functor, Traversable, Foldable)

makeLensesWith
  (lensRules & lensField .~ mappingNamer (pure . (++ "L")))
  ''Logs

type Snapshot state = state

type Term = Int

type Index = Int

data Process pid s = Process
  { processId :: !pid
  , currentTerm :: !Term
  , votedFor :: Maybe pid
  , inputLogs :: !(Logs (Update s))
  , members :: !(HashSet pid)
  , -- | Tentative current state, including uncommitted logs
    tentativeState :: !s
  , -- | Current state, including only upto committed logs.
    committedState :: !s
  , commitIndex :: !Index
  , lastAppliedIndex :: !Index
  , lastAppliedTerm :: !Term
  , processRole :: !(ProcessRole pid)
  }
  deriving (Generic)

deriving instance (Eq (Update s), Eq s, Eq pid) => Eq (Process pid s)

deriving instance (Ord (Update s), Ord s, Ord pid) => Ord (Process pid s)

data FollowerState = FollowerState
  { followerCommitIndex :: !Index
  , followerLastApplied :: !Index
  }
  deriving (Read, Show, Eq, Ord)

data ProcessRole pid
  = Leader
      { followerStates :: !(HashMap pid FollowerState)
      , heartBeatTimer :: Async ()
      }
  | Follower {heartBeatMonitor :: Async ()}
  | Candidate
  deriving (Eq, Ord, Generic)

type Microseconds = Int

data RaftConfig = RaftConfig
  { heartBeatTimeout :: !DiffTime
  , heartBeatPeriod :: !Microseconds
  , candidacyWait :: !DiffTime
  , electionTimeout :: !DiffTime
  }
  deriving (Show, Eq, Ord, Generic)

data RaftMessage pid s
  = AppendEntries
      { raftTerm :: !Term
      , leaderId :: !pid
      , prevLogIndex :: !Index
      , prevLogTerm :: !Term
      , entries :: [Update s]
      , leaderCommit :: !Index
      }
  | RequestVote
      { raftTerm :: !Term
      , candidateId :: !pid
      , lastLogIndex :: !Index
      , lastLogTerm :: !Term
      }
  deriving (Generic)

deriving anyclass instance
  (ToJSON pid, ToJSON (Update s)) => ToJSON (RaftMessage pid s)

deriving anyclass instance
  (FromJSON pid, FromJSON (Update s)) => FromJSON (RaftMessage pid s)

deriving instance (Show pid, Show (Update s)) => Show (RaftMessage pid s)

deriving instance (Eq pid, Eq (Update s)) => Eq (RaftMessage pid s)

deriving instance (Ord pid, Ord (Update s)) => Ord (RaftMessage pid s)

data RaftResponse
  = AppendEntryResult {respTerm :: !Term, success :: !Bool}
  | RequestVoteResult {respTerm :: !Term, voteGranted :: !Bool}
  deriving (Read, Show, Eq, Ord, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | An event in Raft: RPC, result or timeout.
data RaftEvent cid pid s
  = HeartbeatTimeout
  | SendHeartbeat
  | RPC {rpcSender :: !pid, rpcPayload :: RaftMessage pid s}
  | Response RaftResponse
  | ClientRequest {clientId :: cid, request :: ClientRequest s}
  deriving (Generic)

newtype ClientRequest s = AddUpdate [Update s]
  deriving (Generic)

deriving instance Show (Update s) => Show (ClientRequest s)

deriving instance Eq (Update s) => Eq (ClientRequest s)

deriving instance Ord (Update s) => Ord (ClientRequest s)

deriving anyclass instance FromJSON (Update s) => FromJSON (ClientRequest s)

deriving anyclass instance ToJSON (Update s) => ToJSON (ClientRequest s)

deriving instance (Show cid, Show pid, Show (Update s)) => Show (RaftEvent cid pid s)

deriving instance (Eq cid, Eq pid, Eq (Update s)) => Eq (RaftEvent cid pid s)

deriving instance (Ord cid, Ord pid, Ord (Update s)) => Ord (RaftEvent cid pid s)

deriving anyclass instance
  (ToJSON cid, ToJSON pid, ToJSON (Update s)) =>
  ToJSON (RaftEvent cid pid s)

deriving anyclass instance
  (FromJSON cid, FromJSON pid, FromJSON (Update s)) =>
  FromJSON (RaftEvent cid pid s)

data RaftAction pid s
  = SendRPC
      { rpcDest :: !pid
      , rpcReq :: RaftMessage pid s
      }
  | SendRPCResponse {respDest :: !pid, respPayload :: RaftResponse}
  | SendClientResponse
  deriving (Generic)

deriving instance (Show pid, Show (Update s)) => Show (RaftAction pid s)

deriving instance (Eq pid, Eq (Update s)) => Eq (RaftAction pid s)

deriving instance (Ord pid, Ord (Update s)) => Ord (RaftAction pid s)

makeLensesWith
  (lensRules & lensField .~ mappingNamer (pure . (++ "L")))
  ''RaftMessage

makeLensesWith
  (lensRules & lensField .~ mappingNamer (pure . (++ "L")))
  ''Process

makeLensesWith
  (lensRules & lensField .~ mappingNamer (pure . (++ "L")))
  ''ProcessRole
