package msgstore

import (
	"context"
	"strings"
)

// ftsQuery turns what the user typed into a safe FTS query: every word
// becomes a quoted prefix ("orç*"), all of them required. Quotes and FTS
// operators typed by the user never reach FTS raw (inside quotes, AND, OR,
// NOT and parentheses are plain words). "" when there is nothing to search.
func ftsQuery(typed string) string {
	var terms []string
	for _, word := range strings.Fields(typed) {
		word = strings.ReplaceAll(word, `"`, "")
		if word != "" {
			terms = append(terms, `"`+word+`*"`)
		}
	}
	return strings.Join(terms, " ")
}

// Search returns up to limit messages whose text matches typed, ignoring
// accents and case, newest first.
func (s *Store) Search(ctx context.Context, typed string, limit int) ([]Message, error) {
	q := ftsQuery(typed)
	if q == "" {
		return []Message{}, nil
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT `+messageColumns+` FROM cc_messages_fts f
		 JOIN cc_messages m ON m.rowid = f.docid
		 LEFT JOIN cc_media d ON d.chat_jid = m.chat_jid AND d.id = m.id
		 WHERE cc_messages_fts MATCH ? ORDER BY m.ts DESC LIMIT ?`, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
