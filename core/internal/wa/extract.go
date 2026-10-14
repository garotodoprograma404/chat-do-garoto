package wa

import (
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/msgstore"
)

// extract turns a whatsmeow message into one the app stores. ok
// is false for what the app does not show: status updates, reactions, edits,
// protocol messages and key distribution without content.
func extract(evt *events.Message) (msgstore.Message, bool) {
	if evt == nil || evt.Message == nil || evt.Info.Chat.Server == types.BroadcastServer {
		return msgstore.Message{}, false
	}
	m := evt.Message
	if m.GetProtocolMessage() != nil || m.GetReactionMessage() != nil ||
		m.GetEncReactionMessage() != nil || m.GetPollUpdateMessage() != nil || isEmpty(m) {
		return msgstore.Message{}, false
	}

	out := msgstore.Message{
		ChatJID:    evt.Info.Chat.ToNonAD().String(),
		ID:         evt.Info.ID,
		FromMe:     evt.Info.IsFromMe,
		SenderJID:  evt.Info.Sender.ToNonAD().String(),
		SenderName: evt.Info.PushName,
		Timestamp:  evt.Info.Timestamp.UnixMilli(),
	}
	switch {
	case m.GetConversation() != "":
		out.Kind, out.Text = msgstore.KindText, m.GetConversation()
	case m.GetExtendedTextMessage() != nil:
		out.Kind, out.Text = msgstore.KindText, m.GetExtendedTextMessage().GetText()
	case m.GetImageMessage() != nil:
		out.Kind, out.Text = msgstore.KindImage, m.GetImageMessage().GetCaption()
	case m.GetVideoMessage() != nil:
		out.Kind, out.Text = msgstore.KindVideo, m.GetVideoMessage().GetCaption()
	case m.GetAudioMessage() != nil:
		out.Kind = msgstore.KindAudio
	case m.GetDocumentMessage() != nil:
		out.Kind, out.Text = msgstore.KindDocument, m.GetDocumentMessage().GetCaption()
	case m.GetStickerMessage() != nil:
		out.Kind = msgstore.KindSticker
	default:
		out.Kind = msgstore.KindOther
	}
	out.Forwarded = contextOf(m).GetIsForwarded()
	return out, true
}

// contextOf returns the context of a message (forwarded mark, quote…).
func contextOf(m *waE2E.Message) *waE2E.ContextInfo {
	switch {
	case m.GetExtendedTextMessage() != nil:
		return m.GetExtendedTextMessage().GetContextInfo()
	case m.GetImageMessage() != nil:
		return m.GetImageMessage().GetContextInfo()
	case m.GetVideoMessage() != nil:
		return m.GetVideoMessage().GetContextInfo()
	case m.GetAudioMessage() != nil:
		return m.GetAudioMessage().GetContextInfo()
	case m.GetDocumentMessage() != nil:
		return m.GetDocumentMessage().GetContextInfo()
	case m.GetStickerMessage() != nil:
		return m.GetStickerMessage().GetContextInfo()
	}
	return nil
}

// isEmpty reports whether m only carries metadata (for example a sender key
// distribution), with nothing to show.
func isEmpty(m *waE2E.Message) bool {
	c := proto.Clone(m).(*waE2E.Message)
	c.SenderKeyDistributionMessage = nil
	c.MessageContextInfo = nil
	return proto.Size(c) == 0
}
