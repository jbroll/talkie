# tokens.tcl - BERT/WordPiece token constants
# Centralizes magic numbers for token IDs and sequence lengths

namespace eval ::tokens {
    # Special token IDs (standard BERT vocab)
    variable PAD   0      ;# [PAD] - padding token
    variable UNK   100    ;# [UNK] - unknown token
    variable CLS   101    ;# [CLS] - classification token (start of sequence)
    variable SEP   102    ;# [SEP] - separator token (end of sequence)
    variable MASK  103    ;# [MASK] - masked token for MLM

    # Sequence parameters
    variable MAX_SEQ_LEN 64    ;# Maximum sequence length for inference

    # Vocabulary size (standard BERT uncased)
    variable VOCAB_SIZE 30522
}

package provide tokens 1.0
