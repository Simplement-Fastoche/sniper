class User {
  final String name;
  final String email;
  final String avatarUrl;
  final String phoneNumber;
  final String branch;

  User({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.phoneNumber,
    required this.branch,
  });

  // Utilisateur exemple
  static User currentUser() {
    return User(
      name: 'Jean Dupont',
      email: 'jean.dupont@email.com',
      avatarUrl: 'https://i.pravatar.cc/150?img=11',
      phoneNumber: '+243 812 345 678',
      branch: 'Lubumbashi',
    );
  }
}