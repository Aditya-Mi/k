import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/email/readable_text.dart';

void main() {
  test('plain text: padding and stacked blank lines go', () {
    expect(
      readableEmail(
        'Dear  Aditya,\n    \n\n\nAmount Debited:\n INR 25.00\t\n    \nRegards,',
      ),
      'Dear Aditya,\n\nAmount Debited:\nINR 25.00\n\nRegards,',
    );
  });

  test('HTML: tags to lines, cells to spaces, entities decoded', () {
    expect(
      readableEmail(
        '<html><head><style>p{color:red}</style></head><body>'
        '<p>Here&#39;s the summary&nbsp;of your transaction:</p>'
        '<table><tr><td>Amount Debited:</td><td>INR&nbsp;25.00</td></tr>'
        '<tr><td>Account</td><td>XX0640</td></tr></table>'
        '<!-- tracking --><div>Regards,<br>Axis Bank &amp; Co.</div></body></html>',
      ),
      "Here's the summary of your transaction:\n"
      'Amount Debited: INR 25.00\n'
      'Account XX0640\n\n'
      'Regards,\n'
      'Axis Bank & Co.',
    );
  });
}
