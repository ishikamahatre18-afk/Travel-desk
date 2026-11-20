/// What the assistant sends back to the chat screen.
enum ChatActionType {
  pickDates,
  copy,
  whatsapp,
  openLink,
  changePassword,
  newRecovery,
  lock,
  removeAccount,
}

class ChatAction {
  final ChatActionType type;
  final String? text;
  final Uri? uri;
  const ChatAction(this.type, {this.text, this.uri});
}

/// A tappable suggestion. Tapping sends [send] as if the owner typed it,
/// unless [action] is set.
class QuickReply {
  final String label;
  final String send;
  final ChatAction? action;
  const QuickReply(this.label, this.send, {this.action});
}

abstract class Attachment {
  const Attachment();
}

class QuoteCard extends Attachment {
  final String route;
  final String dates;
  final String travellers;
  final String total;
  final String perPerson;
  final bool estimated;
  final List<String> notes;
  const QuoteCard({
    required this.route,
    required this.dates,
    required this.travellers,
    required this.total,
    required this.perPerson,
    required this.estimated,
    this.notes = const [],
  });
}

/// The copy-and-paste message for the client.
class MessageCard extends Attachment {
  final String text;
  const MessageCard(this.text);
}

class FareRow {
  final int index;
  final String airline;
  final String times;
  final String meta;
  final String price;
  final bool cheapest;
  const FareRow({
    required this.index,
    required this.airline,
    required this.times,
    required this.meta,
    required this.price,
    required this.cheapest,
  });
}

class FareCard extends Attachment {
  final String title;
  final String subtitle;
  final String footnote;
  final bool demo;
  final List<FareRow> rows;
  const FareCard({
    required this.title,
    required this.subtitle,
    required this.footnote,
    required this.demo,
    required this.rows,
  });
}

class BotMessage {
  final String text;
  final Attachment? attachment;
  final List<QuickReply> replies;
  final ChatAction? action;
  const BotMessage(
    this.text, {
    this.attachment,
    this.replies = const [],
    this.action,
  });
}

class HotelRow {
  final String name;
  final String meta;
  final String price;
  final bool cheapest;
  const HotelRow({
    required this.name,
    required this.meta,
    required this.price,
    required this.cheapest,
  });
}

class HotelCard extends Attachment {
  final String title;
  final String subtitle;
  final String footnote;
  final bool demo;
  final List<HotelRow> rows;
  const HotelCard({
    required this.title,
    required this.subtitle,
    required this.footnote,
    required this.demo,
    required this.rows,
  });
}
