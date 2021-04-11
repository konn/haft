{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Monad.WithTVar where

import Control.Applicative (Alternative)
import Control.Lens (Lens', magnify, (.~), (^.))
import Control.Monad (MonadPlus)
import Control.Monad.Catch (MonadCatch, MonadThrow)
import Control.Monad.Reader (ReaderT, ask, runReaderT)
import Control.Monad.STM.Class (MonadSTM (newTVar))
import Control.Monad.State.Class (MonadState (..))
import Control.Monad.Trans (lift)
import UnliftIO.STM (STM, TVar, modifyTVar', readTVar, writeTVar)

-- | 'STM'-based state monad by focusing on some 'TVar'.
newtype WithTVarM s a = WithTVarM
  {runWithTVarM_ :: ReaderT (TVar s) STM a}
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , Alternative
    , MonadPlus
    , MonadThrow
    , MonadCatch
    , MonadSTM
    )

instance MonadState s (WithTVarM s) where
  get = WithTVarM $ lift . readTVar =<< ask
  {-# INLINE get #-}
  put w = WithTVarM $ lift . flip writeTVar w =<< ask
  {-# INLINE put #-}

focus :: Lens' s t -> WithTVarM t a -> WithTVarM s a
focus l (WithTVarM act) = WithTVarM $ do
  tv <- ask
  val <- lift $ readTVar tv
  stv <- newTVar $ val ^. l
  a <- lift $ runReaderT act stv
  val' <- lift $ readTVar stv
  lift $ modifyTVar' tv $ l .~ val'
  pure a
