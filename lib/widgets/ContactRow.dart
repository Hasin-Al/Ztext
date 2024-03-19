import 'package:flutter/material.dart';
import 'package:shosti/main.dart';

class ContactRow extends StatelessWidget {
  final MyContact myContact;
  final deleteContact;
  final int index;

  const ContactRow(this.myContact, this.deleteContact, this.index, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  myContact.name,
                  style: const TextStyle(
                    fontSize: 24,
                  ),
                ),
                Text(
                  myContact.number,
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: () {
                deleteContact(index);
              },
              icon: const Icon(Icons.delete),
            ),
          ],
        ),
      ),
    );
  }
}
