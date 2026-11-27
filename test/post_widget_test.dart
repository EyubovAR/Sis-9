// SRS 9 — Widget Test.
//
// Тестируются реальные экраны приложения Post Explorer:
// PostListScreen (главный), PostDetailScreen и CreatePostScreen.
// Запускается настоящий MyApp из lib/main.dart, подменён только
// PostRepository (mocktail), чтобы тесты не ходили в сеть.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:srs8/core/error/app_exception.dart';
import 'package:srs8/data/models/comment.dart';
import 'package:srs8/data/models/post.dart';
import 'package:srs8/data/models/user.dart';
import 'package:srs8/data/repositories/post_repository.dart';
import 'package:srs8/main.dart';
import 'package:srs8/presentation/screens/create_post_screen.dart';
import 'package:srs8/presentation/screens/post_detail_screen.dart';
import 'package:srs8/presentation/screens/post_list_screen.dart';
import 'package:srs8/presentation/widgets/post_card.dart';

class MockPostRepository extends Mock implements PostRepository {}

const _posts = [
  Post(id: 1, userId: 1, title: 'Flutter basics', body: 'Widgets and layouts'),
  Post(id: 2, userId: 1, title: 'Dart streams', body: 'Async programming'),
  Post(id: 3, userId: 2, title: 'Flutter BLoC', body: 'State management'),
];

const _users = [
  User(id: 1, name: 'Leanne Graham', username: 'Bret', email: 'leanne@test.io'),
  User(id: 2, name: 'Ervin Howell', username: 'Antonette', email: 'ervin@test.io'),
];

const _comments = [
  Comment(
    id: 1,
    postId: 1,
    name: 'Отличный пост',
    email: 'reader@test.io',
    body: 'Спасибо, очень полезно!',
  ),
];

void main() {
  late MockPostRepository repository;

  setUp(() {
    repository = MockPostRepository();

    when(() => repository.getCachedPosts()).thenAnswer((_) async => []);
    when(() => repository.getUsers()).thenAnswer((_) async => _users);
    when(() => repository.getComments(any())).thenAnswer((_) async => _comments);
    when(() => repository.getPosts(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          userId: any(named: 'userId'),
        )).thenAnswer(
      (_) async => FetchPostsResult(posts: _posts, isFromCache: false),
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
  }

  // Вертикальная позиция карточки поста на экране (для проверки порядка).
  double cardY(WidgetTester tester, String title) =>
      tester.getTopLeft(find.text(title)).dy;

  group('PostListScreen — главный экран', () {
    testWidgets('1. Отображаются заголовок, поиск, кнопки и карточки постов',
        (tester) async {
      await pumpApp(tester);

      // Основной экран и его заголовок
      expect(find.byType(PostListScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Post Explorer'), findsOneWidget);

      // Основные элементы интерфейса и кнопки
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.widgetWithIcon(FloatingActionButton, Icons.add), findsOneWidget);

      // Список постов из репозитория
      expect(find.byType(PostCard), findsNWidgets(3));
      expect(find.text('Flutter basics'), findsOneWidget);
      expect(find.text('#1 • Автор: 1'), findsOneWidget);
      expect(find.text('State management'), findsOneWidget);
    });

    testWidgets('2. Кнопка сортировки меняет иконку и порядок постов',
        (tester) async {
      await pumpApp(tester);

      // До нажатия: по возрастанию ID
      expect(cardY(tester, 'Flutter basics'), lessThan(cardY(tester, 'Flutter BLoC')));

      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      // После нажатия: иконка сменилась, порядок перевернулся
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(cardY(tester, 'Flutter BLoC'), lessThan(cardY(tester, 'Flutter basics')));
    });

    testWidgets('3. Ввод в поле поиска фильтрует список', (tester) async {
      await pumpApp(tester);

      await tester.enterText(find.byType(TextField), 'dart');
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsOneWidget);
      expect(find.text('Dart streams'), findsOneWidget);
      expect(find.text('Flutter basics'), findsNothing);
    });

    testWidgets('4. Некорректный запрос: поиск без совпадений → «Посты не найдены.»',
        (tester) async {
      await pumpApp(tester);

      await tester.enterText(find.byType(TextField), '!!! нет такого ???');
      await tester.pumpAndSettle();

      expect(find.byType(PostCard), findsNothing);
      expect(find.text('Посты не найдены.'), findsOneWidget);
    });

    testWidgets('5. Несколько элементов вместе: поиск + сортировка',
        (tester) async {
      await pumpApp(tester);

      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      // Остались только посты с «Flutter», и они идут по убыванию ID
      expect(find.byType(PostCard), findsNWidgets(2));
      expect(find.text('Dart streams'), findsNothing);
      expect(cardY(tester, 'Flutter BLoC'), lessThan(cardY(tester, 'Flutter basics')));
    });

    testWidgets('6. Фильтр по автору: диалог, выбор автора и сброс',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      expect(find.text('Выберите автора'), findsOneWidget);
      expect(find.text('Все авторы'), findsOneWidget);
      expect(find.text('Ervin Howell'), findsOneWidget);

      await tester.tap(find.text('Ervin Howell'));
      await tester.pumpAndSettle();

      // Диалог закрылся, появилась плашка фильтра, посты запрошены по автору
      expect(find.text('Выберите автора'), findsNothing);
      expect(find.text('Фильтр: Автор ID 2'), findsOneWidget);
      verify(() => repository.getPosts(page: 1, limit: 10, userId: 2)).called(1);

      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();

      expect(find.text('Фильтр: Автор ID 2'), findsNothing);
    });

    testWidgets('7. Ошибка загрузки: сообщение и рабочая кнопка «Повторить попытку»',
        (tester) async {
      var attempts = 0;
      when(() => repository.getPosts(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            userId: any(named: 'userId'),
          )).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw NetworkException();
        return FetchPostsResult(posts: _posts, isFromCache: false);
      });

      await pumpApp(tester);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Отсутствует интернет-соединение'), findsOneWidget);
      expect(find.byType(PostCard), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Повторить попытку'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(PostCard), findsNWidgets(3));
    });
  });

  group('Переходы между экранами', () {
    testWidgets('8. Нажатие на карточку открывает экран поста с комментариями',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Flutter basics'));
      await tester.pumpAndSettle();

      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Пост #1'), findsOneWidget);
      expect(find.text('Автор ID: 1'), findsOneWidget);
      expect(find.text('Комментарии'), findsOneWidget);
      expect(find.text('Отличный пост'), findsOneWidget);
      expect(find.text('Спасибо, очень полезно!'), findsOneWidget);
      verify(() => repository.getComments(1)).called(1);

      // Возврат назад на главный экран
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(PostDetailScreen), findsNothing);
      expect(find.widgetWithText(AppBar, 'Post Explorer'), findsOneWidget);
    });

    testWidgets('9. Создание поста: пустая форма не отправляется, показаны ошибки',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(CreatePostScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Создать пост'), findsOneWidget);

      // Некорректные данные: пустой заголовок и слишком короткий текст
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Содержимое (от 10 до 1000 символов)'),
        'мало',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Опубликовать'));
      await tester.pumpAndSettle();

      expect(
        find.text('Длина заголовка должна быть от 5 до 100 символов'),
        findsOneWidget,
      );
      expect(
        find.text('Длина текста должна быть от 10 до 1000 символов'),
        findsOneWidget,
      );
      expect(find.byType(CreatePostScreen), findsOneWidget); // остались на форме
      verifyNever(() => repository.createPost(
            title: any(named: 'title'),
            body: any(named: 'body'),
            userId: any(named: 'userId'),
          ));
    });

    testWidgets('10. Создание поста: корректные данные → возврат и новый пост в списке',
        (tester) async {
      when(() => repository.createPost(
            title: any(named: 'title'),
            body: any(named: 'body'),
            userId: any(named: 'userId'),
          )).thenAnswer((invocation) async => Post(
            id: 101,
            userId: invocation.namedArguments[#userId] as int,
            title: invocation.namedArguments[#title] as String,
            body: invocation.namedArguments[#body] as String,
            isLocallyCreated: true,
          ));

      await pumpApp(tester);
      expect(find.text('Создан локально'), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Заголовок (от 5 до 100 символов)'),
        'Мой новый пост',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Содержимое (от 10 до 1000 символов)'),
        'Текст нового поста для проверки.',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Опубликовать'));
      await tester.pumpAndSettle();

      // Вернулись на главный экран, пост добавлен и помечен как локальный
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(find.text('Пост успешно создан!'), findsOneWidget);
      expect(find.byType(PostCard), findsNWidgets(4));
      expect(find.text('Мой новый пост'), findsOneWidget);
      expect(find.text('Создан локально'), findsOneWidget);
      verify(() => repository.createPost(
            title: 'Мой новый пост',
            body: 'Текст нового поста для проверки.',
            userId: 1,
          )).called(1);
    });
  });
}
