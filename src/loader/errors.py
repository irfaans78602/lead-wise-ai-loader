"""Exception types raised by the loader."""


class LoaderError(Exception):
    """Base class for every loader-raised error."""


class ConfigError(LoaderError):
    """Environment or CLI configuration is wrong."""


class FileError(LoaderError):
    """Input JSON is missing or malformed."""


class PreflightError(LoaderError):
    """
    One or more preflight checks failed. Carries a list of messages
    so the caller can print them all instead of the first.
    """
    def __init__(self, messages):
        self.messages = list(messages)
        super().__init__(f"{len(self.messages)} preflight error(s)")


class WriteError(LoaderError):
    """A write failed after preflight passed. The transaction is
    rolled back by the caller."""