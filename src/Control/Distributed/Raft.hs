{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Control.Distributed.Raft where

import Control.Distributed.Raft.Types
import Control.Lens (use, (%=), (+=), (.=), (.~), (^.), (^..))
import Control.Monad (forever)
import Control.Monad.State.Class (MonadState, get)
import Data.Foldable (foldl', forM_)
import qualified Data.HashMap.Strict as HM
import Data.Hashable (Hashable)
import qualified Data.Sequence as Seq
import Pipes
import UnliftIO

mkAppendEntry ::
  ( MonadState (Process pid state) m
  , Transition state
  ) =>
  [Update state] ->
  m (RaftMessage pid state)
mkAppendEntry upds = do
  let !len = length upds
  Process {..} <- get
  lastAppliedTermL .= currentTerm
  lastAppliedIndexL += len
  tentativeStateL %= \s -> foldl' transition s upds
  inputLogsL . logsL %= (<> Seq.fromList upds)
  pure
    AppendEntries
      { raftTerm = currentTerm
      , leaderId = processId
      , prevLogIndex = lastAppliedIndex
      , prevLogTerm = lastAppliedTerm
      , entries = upds
      , leaderCommit = commitIndex
      }

-- FIXME: Rewrite using STM to ensure atomicity
serverLoop ::
  ( MonadUnliftIO m
  , MonadState (Process pid s) m
  , Transition s
  , Eq pid
  , Hashable pid
  ) =>
  Pipe (RaftEvent cid pid s) (RaftAction pid s) m r
serverLoop = forever $ do
  await >>= \case
    HeartbeatTimeout -> undefined
    SendHeartbeat -> do
      self <- get
      msg <- mkAppendEntry []
      forM_ (HM.toList $ self ^. processRoleL . followerStatesL) $
        \(pid, FollowerState {}) ->
          yield $ SendRPC {rpcDest = pid, rpcReq = msg}
    (RPC pid rs) -> do
      term <- use currentTermL
      case rs of
        _ | term < rs ^. raftTermL -> do
          currentTermL .= term
          convertToFollower
        AppendEntries {..} -> _
        RequestVote {..} -> _
    (Response r) -> undefined
    ClientRequest cid (AddUpdate ls) -> undefined

convertToFollower ::
  ( MonadUnliftIO m
  , MonadState (Process pid s) m
  ) =>
  m ()
convertToFollower = do
  processRoleL .~ Follower undefined
