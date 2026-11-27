// SRS 9 — Unit Test.
//
// Тестируется реальная логика приложения Post Explorer (без интерфейса):
//  * CreatePostCubit.submitPost — проверка введённых данных при создании поста;
//  * PostBloc — поиск, сортировка, пагинация и обработка ошибок загрузки.
//
// Сеть не используется: PostRepository подменён моком (mocktail).

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:srs8/core/error/app_exception.dart';
import 'package:srs8/data/models/post.dart';
import 'package:srs8/data/repositories/post_repository.dart';
import 'package:srs8/presentation/state/create_post_cubit.dart';
import 'package:srs8/presentation/state/post_bloc.dart';
import 'package:srs8/presentation/state/post_event.dart';
import 'package:srs8/presentation/state/post_state.dart';

class MockPostRepository extends Mock implements PostRepository {}

void main() {
  late MockPostRepository repository;

  setUp(() {
    repository = MockPostRepository();
  });

  group('CreatePostCubit.submitPost — валидация данных поста', () {
    late CreatePostCubit cubit;
    late List<CreatePostState> states;

    const validTitle = 'Мой первый пост';
    const validBody = 'Достаточно длинный текст поста.';

    setUp(() {
      cubit = CreatePostCubit(repository: repository);
      states = [];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(cubit.close);
    });

    // Заглушка успешного ответа сервера: возвращает пост с теми же данными.
    void stubCreateSuccess() {
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
    }

    void verifyRepositoryNotCalled() {
      verifyNever(() => repository.createPost(
            title: any(named: 'title'),
            body: any(named: 'body'),
            userId: any(named: 'userId'),
          ));
    }

    test('1. Начальное состояние — initial, без поста и без ошибки', () {
      expect(cubit.state.status, CreateStatus.initial);
      expect(cubit.state.createdPost, isNull);
      expect(cubit.state.errorMessage, isNull);
    });

    test('2. Слишком короткий заголовок (< 5 символов) отклоняется', () async {
      await cubit.submitPost(title: 'Hey', body: validBody, userId: 1);

      expect(cubit.state.status, CreateStatus.error);
      expect(
        cubit.state.errorMessage,
        'Заголовок должен содержать от 5 до 100 символов',
      );
      verifyRepositoryNotCalled();
    });

    test('3. Слишком длинный заголовок (> 100 символов) отклоняется', () async {
      await cubit.submitPost(title: 'a' * 101, body: validBody, userId: 1);

      expect(cubit.state.status, CreateStatus.error);
      expect(cubit.state.errorMessage, contains('от 5 до 100'));
      verifyRepositoryNotCalled();
    });

    test('4. Заголовок из одних пробелов считается пустым', () async {
      await cubit.submitPost(title: ' ' * 20, body: validBody, userId: 1);

      expect(cubit.state.status, CreateStatus.error);
      expect(cubit.state.errorMessage, contains('Заголовок'));
      verifyRepositoryNotCalled();
    });

    test('5. Слишком короткий текст (< 10 символов) отклоняется', () async {
      await cubit.submitPost(title: validTitle, body: 'Коротко', userId: 1);

      expect(cubit.state.status, CreateStatus.error);
      expect(
        cubit.state.errorMessage,
        'Текст поста должен содержать от 10 до 1000 символов',
      );
      verifyRepositoryNotCalled();
    });

    test('6. Слишком длинный текст (> 1000 символов) отклоняется', () async {
      await cubit.submitPost(title: validTitle, body: 'b' * 1001, userId: 1);

      expect(cubit.state.status, CreateStatus.error);
      expect(cubit.state.errorMessage, contains('от 10 до 1000'));
      verifyRepositoryNotCalled();
    });

    test('7. Граничные значения (5 и 10 символов) принимаются', () async {
      stubCreateSuccess();

      await cubit.submitPost(title: '12345', body: '1234567890', userId: 1);

      expect(cubit.state.status, CreateStatus.success);
    });

    test('8. Корректные данные: submitting → success, пробелы обрезаются',
        () async {
      stubCreateSuccess();

      await cubit.submitPost(
        title: '  $validTitle  ',
        body: '  $validBody  ',
        userId: 7,
      );
      await pumpEventQueue();

      expect(
        states.map((s) => s.status),
        [CreateStatus.submitting, CreateStatus.success],
      );
      expect(cubit.state.createdPost?.title, validTitle);
      expect(cubit.state.createdPost?.userId, 7);
      verify(() => repository.createPost(
            title: validTitle,
            body: validBody,
            userId: 7,
          )).called(1);
    });

    test('9. Ошибка сети при отправке переводит в состояние error', () async {
      when(() => repository.createPost(
            title: any(named: 'title'),
            body: any(named: 'body'),
            userId: any(named: 'userId'),
          )).thenThrow(NetworkException());

      await cubit.submitPost(title: validTitle, body: validBody, userId: 1);

      expect(cubit.state.status, CreateStatus.error);
      expect(cubit.state.errorMessage, contains('интернет-соединение'));
      expect(cubit.state.createdPost, isNull);
    });
  });

  group('PostBloc — поиск, сортировка и загрузка постов', () {
    // Посты приходят с сервера в произвольном порядке.
    const posts = [
      Post(id: 3, userId: 2, title: 'Flutter BLoC', body: 'State management'),
      Post(id: 1, userId: 1, title: 'Flutter basics', body: 'Widgets'),
      Post(id: 2, userId: 1, title: 'Dart streams', body: 'Async'),
    ];

    void stubPosts(List<Post> page1, {bool isFromCache = false}) {
      when(() => repository.getPosts(
            page: 1,
            limit: 10,
            userId: any(named: 'userId'),
          )).thenAnswer(
        (_) async => FetchPostsResult(posts: page1, isFromCache: isFromCache),
      );
    }

    Future<PostBloc> loadBloc() async {
      final bloc = PostBloc(repository: repository)..add(LoadPostsEvent());
      addTearDown(bloc.close);
      await pumpEventQueue();
      return bloc;
    }

    List<int?> ids(PostBloc bloc) =>
        bloc.state.filteredPosts.map((p) => p.id).toList();

    setUp(() {
      when(() => repository.getCachedPosts()).thenAnswer((_) async => []);
    });

    test('10. После загрузки посты отсортированы по ID по возрастанию',
        () async {
      stubPosts(posts);

      final bloc = await loadBloc();

      expect(bloc.state.status, PostStatus.success);
      expect(ids(bloc), [1, 2, 3]);
      expect(bloc.state.hasReachedMax, isTrue); // пришло меньше 10 постов
    });

    test('11. Поиск по заголовку не зависит от регистра и пробелов', () async {
      stubPosts(posts);
      final bloc = await loadBloc();

      bloc.add(SearchPostsEvent('  FLUTTER '));
      await pumpEventQueue();

      expect(ids(bloc), [1, 3]);
      expect(bloc.state.posts.length, 3); // исходный список не меняется
    });

    test('12. Поиск без совпадений даёт пустой результат (isEmpty)', () async {
      stubPosts(posts);
      final bloc = await loadBloc();

      bloc.add(SearchPostsEvent('нет такого поста'));
      await pumpEventQueue();

      expect(bloc.state.filteredPosts, isEmpty);
      expect(bloc.state.isEmpty, isTrue);
    });

    test('13. Сортировка по убыванию переворачивает порядок', () async {
      stubPosts(posts);
      final bloc = await loadBloc();

      bloc.add(SortPostsEvent(ascending: false));
      await pumpEventQueue();

      expect(bloc.state.isAscending, isFalse);
      expect(ids(bloc), [3, 2, 1]);
    });

    test('14. Подгрузка второй страницы добавляет посты в конец', () async {
      final firstPage = List.generate(
        10,
        (i) => Post(id: i + 1, userId: 1, title: 'Post ${i + 1}', body: 'Body'),
      );
      stubPosts(firstPage);
      when(() => repository.getPosts(
            page: 2,
            limit: 10,
            userId: any(named: 'userId'),
          )).thenAnswer((_) async => FetchPostsResult(
            posts: const [
              Post(id: 11, userId: 1, title: 'Post 11', body: 'Body'),
            ],
            isFromCache: false,
          ));
      final bloc = await loadBloc();
      expect(bloc.state.hasReachedMax, isFalse);

      bloc.add(LoadMorePostsEvent());
      await pumpEventQueue();

      expect(bloc.state.posts.length, 11);
      expect(bloc.state.currentPage, 2);
      expect(bloc.state.hasReachedMax, isTrue);
      expect(bloc.state.isLoadingMore, isFalse);
    });

    test('15. Ошибка загрузки без кэша → статус error с текстом ошибки',
        () async {
      when(() => repository.getPosts(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            userId: any(named: 'userId'),
          )).thenThrow(NetworkException());

      final bloc = await loadBloc();

      expect(bloc.state.status, PostStatus.error);
      expect(bloc.state.errorMessage, contains('интернет-соединение'));
      expect(bloc.state.posts, isEmpty);
    });

    test('16. Некорректный объект в AddCreatedPostEvent игнорируется',
        () async {
      stubPosts(posts);
      final bloc = await loadBloc();

      bloc.add(AddCreatedPostEvent('это не пост'));
      bloc.add(AddCreatedPostEvent(null));
      await pumpEventQueue();

      expect(bloc.state.posts.length, 3);
    });
  });
}
